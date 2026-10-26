use crate::bluetooth::{BtService, BtStatus};
use crate::hid;
use crate::focus;
use crate::levels;
use crate::inject::{Injector, Input};
use crate::leds;
use crate::portowner::{self, Owner};
use futures_util::{SinkExt, StreamExt};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};
use tokio::net::TcpListener;
use tokio::runtime::Runtime;
use tokio::sync::{broadcast, watch};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};

pub const DEFAULT_PORT: u16 = 8765;

/// The app sends this one-byte frame every second; the agent ignores its content.
pub const KEEPALIVE: u8 = 0x00;

/// A phone that has sent nothing for this long is treated as gone (the app sends a
/// keep-alive every second). Dropping it lets the phone fail over to its other link.
pub const CLIENT_TIMEOUT: Duration = if cfg!(test) { Duration::from_secs(1) } else { Duration::from_secs(5) };

pub type SharedState = Arc<Mutex<Shared>>;
pub type SharedInput = Arc<Mutex<Input>>;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Transport {
    WiFi,
    #[cfg_attr(windows, allow(dead_code))]
    Bluetooth,
}

impl Transport {
    pub fn label(self) -> &'static str {
        match self {
            Transport::WiFi => "Wi-Fi",
            Transport::Bluetooth => "Bluetooth",
        }
    }
}

#[derive(Clone)]
pub struct Client {
    pub id: u64,
    pub transport: Transport,
    pub addr: String,
}

#[derive(Default)]
pub struct Shared {
    pub token: String,
    pub running: bool,
    pub error: Option<String>,
    pub clients: Vec<Client>,
    pub log: Vec<String>,
    pub bt: BtStatus,
    /// The port the Wi-Fi server listens on (told to phones on the USB cable).
    pub port: u16,
    /// Phones plugged in with a USB cable.
    pub usb: crate::usb::UsbStatus,
    /// Set when the port is taken: who holds it.
    pub port_owner: Option<Owner>,
    /// Speech to text / to action for the phone's voice screen (see voice.rs).
    pub voice: Arc<crate::voice::Engine>,
    pub media_requests: Option<std::sync::mpsc::SyncSender<crate::media::SeekRequest>>,
    pub(crate) next_id: u64,
}

impl Shared {
    pub fn log(&mut self, line: impl Into<String>) {
        let line = line.into();
        println!("{line}");
        self.log.push(line);
        if self.log.len() > 200 {
            self.log.remove(0);
        }
    }
}

/// Random bytes from the operating system.
pub fn random_bytes(buf: &mut [u8]) {
    #[cfg(unix)]
    std::fs::File::open("/dev/urandom")
        .and_then(|mut f| std::io::Read::read_exact(&mut f, buf))
        .expect("read /dev/urandom");
    #[cfg(windows)]
    {
        use windows_sys::Win32::Security::Cryptography::{BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG};
        // SAFETY: the buffer is valid for its whole length; the flag asks for the system RNG.
        let status = unsafe {
            BCryptGenRandom(std::ptr::null_mut(), buf.as_mut_ptr(), buf.len() as u32, BCRYPT_USE_SYSTEM_PREFERRED_RNG)
        };
        assert!(status >= 0, "BCryptGenRandom failed");
    }
}

pub fn make_token() -> String {
    // 8 random bytes: the token is kept for good now, so it is longer than it was.
    let mut buf = [0u8; 8];
    random_bytes(&mut buf);
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

/// Best-effort LAN address (connecting a UDP socket sends no packets).
pub fn local_ip() -> Option<String> {
    let s = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    s.connect("8.8.8.8:80").ok()?;
    Some(s.local_addr().ok()?.ip().to_string())
}

/// Constant-time comparison so response time doesn't leak how much matched.
pub fn token_ok(shared: &SharedState, candidate: &[u8]) -> bool {
    let s = shared.lock().unwrap();
    let want = s.token.as_bytes();
    want.len() == candidate.len()
        && want.iter().zip(candidate).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
}

/// Wrong-token connections wait this long before being dropped, which makes
/// guessing the token over the network impractically slow.
pub const BAD_TOKEN_DELAY: Duration = Duration::from_millis(800);

pub fn register_client(shared: &SharedState, transport: Transport, addr: String) -> u64 {
    let mut s = shared.lock().unwrap();
    s.next_id += 1;
    let id = s.next_id;
    s.log(format!("{} {addr} connected", transport.label()));
    s.clients.push(Client { id, transport, addr });
    id
}

/// Remove a client. When the last phone is gone, release anything it left held.
pub fn unregister_client(shared: &SharedState, input: &SharedInput, id: u64) {
    let idle = {
        let mut s = shared.lock().unwrap();
        if let Some(pos) = s.clients.iter().position(|c| c.id == id) {
            let c = s.clients.remove(pos);
            s.log(format!("{} {} disconnected", c.transport.label(), c.addr));
        }
        s.clients.is_empty()
    };
    if idle {
        input.lock().unwrap().release_all();
    }
}

pub fn apply_bytes(input: &SharedInput, data: &[u8]) {
    if let Some(ev) = hid::parse(data) {
        if let Err(e) = input.lock().unwrap().apply(ev) {
            eprintln!("inject error: {e}");
        }
    }
}

pub struct Server {
    rt: Runtime,
    pub shared: SharedState,
    stop: Option<watch::Sender<bool>>,
    bt: Option<BtService>,
    /// Lock-key lights, pushed to phones over Wi-Fi (Bluetooth is sent directly).
    led_tx: watch::Sender<u8>,
    led_stop: Arc<AtomicBool>,
    led_thread: Option<JoinHandle<()>>,
    level_tx: watch::Sender<levels::Levels>,
    level_thread: Option<JoinHandle<()>>,
    event_tx: broadcast::Sender<Vec<u8>>,
    focus_thread: Option<JoinHandle<()>>,
    media_thread: Option<JoinHandle<()>>,
    /// Find and connect phones plugged in with a USB cable (see usb.rs).
    pub usb_auto: Arc<AtomicBool>,
    usb_thread: Option<JoinHandle<()>>,
}

impl Server {
    pub fn new(token: String) -> Self {
        let shared = Shared { token, ..Default::default() };
        Self {
            rt: Runtime::new().expect("tokio runtime"),
            shared: Arc::new(Mutex::new(shared)),
            stop: None,
            bt: None,
            led_tx: watch::channel(leds::UNKNOWN).0,
            led_stop: Arc::new(AtomicBool::new(false)),
            led_thread: None,
            level_tx: watch::channel(levels::NOTHING).0,
            level_thread: None,
            event_tx: broadcast::channel(256).0,
            focus_thread: None,
            media_thread: None,
            // Off in tests: servers started there must not go looking for a real phone.
            // DESK_NO_USB=1 turns it off from the start (for tests and demos).
            usb_auto: Arc::new(AtomicBool::new(!cfg!(test) && std::env::var_os("DESK_NO_USB").is_none())),
            usb_thread: None,
        }
    }

    pub fn start(&mut self, port: u16) {
        if self.stop.is_some() {
            return;
        }
        // Take the port first. If it is busy, nothing else is started, so pressing Start
        // again later works (a half-started server would silently ignore it).
        let listener = match self.rt.block_on(TcpListener::bind(("0.0.0.0", port))) {
            Ok(l) => l,
            Err(e) => {
                let owner = portowner::listener(port);
                let mut s = self.shared.lock().unwrap();
                s.running = false;
                s.error = Some(match &owner {
                    Some(o) => format!("Port {port} is already in use by {}.", o.describe()),
                    None => format!("Cannot listen on port {port}: {e}"),
                });
                s.port_owner = owner;
                return;
            }
        };
        let injector = match Injector::new() {
            Ok(i) => i,
            Err(e) => {
                let mut s = self.shared.lock().unwrap();
                s.error = Some(format!("Cannot create virtual input device: {e} (check /dev/uinput permissions)"));
                s.port_owner = None;
                return; // the listener is dropped here, freeing the port again
            }
        };
        let input: SharedInput = Arc::new(Mutex::new(Input::new(Box::new(injector))));
        let (tx, rx) = watch::channel(false);
        self.stop = Some(tx);
        {
            let mut s = self.shared.lock().unwrap();
            s.error = None;
            s.port_owner = None;
            s.running = true;
            s.port = port;
            s.log(format!("Listening on port {port}"));
        }
        let bt = BtService::start(self.shared.clone(), input.clone());
        self.led_stop.store(false, Ordering::Relaxed);
        self.led_thread = Some(leds::spawn(self.led_stop.clone(), self.led_tx.clone(), bt.broadcaster()));
        self.level_thread = Some(levels::spawn(self.led_stop.clone(), self.level_tx.clone(), bt.broadcaster()));
        let (ev, send_bt) = (self.event_tx.clone(), Mutex::new(bt.broadcaster()));
        self.focus_thread = Some(focus::spawn(self.led_stop.clone(), move |typeable| {
            let frame = [focus::FRAME_ID, typeable as u8];
            let _ = ev.send(frame.to_vec()); // Err just means nobody is listening
            (send_bt.lock().unwrap())(&frame);
        }));
        self.usb_thread = Some(crate::usb::spawn(
            self.led_stop.clone(),
            self.shared.clone(),
            port,
            self.usb_auto.clone(),
        ));
        let (ev, send_bt) = (self.event_tx.clone(), Mutex::new(bt.broadcaster()));
        let (media_tx, media_rx) = std::sync::mpsc::sync_channel(8);
        self.shared.lock().unwrap().media_requests = Some(media_tx);
        self.media_thread = Some(crate::media::spawn(self.led_stop.clone(), move |frame| {
            let _ = ev.send(frame.to_vec());
            (send_bt.lock().unwrap())(frame);
        }, media_rx));
        self.bt = Some(bt);
        self.rt.spawn(accept_loop(listener, self.shared.clone(), input, rx, self.led_tx.subscribe(), self.level_tx.subscribe(), self.event_tx.clone()));
    }

    /// Stop and start again on the same port. Connected phones are dropped and
    /// reconnect on their own.
    pub fn restart(&mut self, port: u16) {
        self.shared.lock().unwrap().log("Restarting...");
        self.stop();
        self.start(port);
    }

    pub fn stop(&mut self) {
        if let Some(tx) = self.stop.take() {
            let _ = tx.send(true);
        }
        self.led_stop.store(true, Ordering::Relaxed);
        if let Some(t) = self.led_thread.take() {
            let _ = t.join();
        }
        if let Some(t) = self.level_thread.take() {
            let _ = t.join();
        }
        if let Some(t) = self.focus_thread.take() {
            let _ = t.join();
        }
        if let Some(t) = self.media_thread.take() { let _ = t.join(); }
        if let Some(t) = self.usb_thread.take() {
            let _ = t.join();
        }
        if let Some(mut bt) = self.bt.take() {
            bt.stop();
        }
        // The port is only free once the accept loop has dropped its listener.
        for _ in 0..100 {
            if !self.shared.lock().unwrap().running {
                break;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}

async fn accept_loop(
    listener: TcpListener,
    shared: SharedState,
    input: SharedInput,
    mut stop: watch::Receiver<bool>,
    leds: watch::Receiver<u8>,
    levels: watch::Receiver<levels::Levels>,
    events: broadcast::Sender<Vec<u8>>,
) {
    loop {
        tokio::select! {
            _ = stop.changed() => break,
            res = listener.accept() => {
                let Ok((stream, addr)) = res else { continue };
                tokio::spawn(handle_client(stream, addr.to_string(), shared.clone(), input.clone(), stop.clone(), leds.clone(), levels.clone(), events.subscribe()));
            }
        }
    }
    drop(listener); // release the port before reporting "stopped"
    let mut s = shared.lock().unwrap();
    s.running = false;
    s.clients.retain(|c| c.transport != Transport::WiFi);
    s.log("Wi-Fi server stopped");
}

fn level_frame(l: levels::Levels) -> Message {
    Message::Binary(vec![levels::FRAME_ID, l[0], l[1], l[2]].into())
}

async fn handle_client(
    stream: tokio::net::TcpStream,
    addr: String,
    shared: SharedState,
    input: SharedInput,
    mut stop: watch::Receiver<bool>,
    mut led_rx: watch::Receiver<u8>,
    mut level_rx: watch::Receiver<levels::Levels>,
    mut event_rx: broadcast::Receiver<Vec<u8>>,
) {
    // Audio has its own WebSocket on the same authenticated port. Keeping it off the input
    // socket means a full audio queue can never delay a key-up or pointer packet.
    let audio_path = Arc::new(AtomicBool::new(false));
    let route = audio_path.clone();
    let Ok(mut ws) = tokio_tungstenite::accept_hdr_async(
        stream,
        move |request: &Request, response: Response| {
            route.store(request.uri().path() == crate::audio::PATH, Ordering::Relaxed);
            Ok(response)
        },
    ).await else { return };
    // First frame must be a text message carrying the token.
    let ok = match ws.next().await {
        Some(Ok(Message::Text(t))) => token_ok(&shared, t.as_bytes()),
        _ => false,
    };
    if !ok {
        shared.lock().unwrap().log(format!("Wi-Fi {addr} rejected (bad token)"));
        tokio::time::sleep(BAD_TOKEN_DELAY).await;
        return;
    }
    // Tell the phone the token was accepted so it can show "connected" truthfully.
    if ws.send(Message::Text("ok".into())).await.is_err() {
        return;
    }
    if audio_path.load(Ordering::Relaxed) {
        crate::audio::handle(ws, shared, stop).await;
        return;
    }
    let label = addr.clone();
    let on_cable = crate::identity::is_loopback(&addr);
    let id = register_client(&shared, Transport::WiFi, addr);
    // Voice answers come from worker threads; this channel brings them to the socket.
    let (voice_tx, mut voice_rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
    let engine = shared.lock().unwrap().voice.clone();
    let mut voice = crate::voice::VoiceSession::new(engine, Arc::new(move |f| drop(voice_tx.send(f))));
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    let mut last_rx = Instant::now();
    // Older apps send no keep-alives; they are never timed out.
    let mut keepalives = false;
    // Tell the phone the current lock lights straight away.
    let current = *led_rx.borrow_and_update();
    if current != leds::UNKNOWN
        && ws.send(Message::Binary(vec![leds::FRAME_ID, current].into())).await.is_err()
    {
        unregister_client(&shared, &input, id);
        return;
    }
    if on_cable {
        // A phone on the USB cable: tell it how to reach this computer by Wi-Fi and Bluetooth, so
        // those links can be set up with no QR code, and the computer is not added twice.
        let (port, bt) = {
            let s = shared.lock().unwrap();
            (s.port, s.bt.adapter.clone())
        };
        let frame = crate::identity::info_frame(local_ip().as_deref(), port, bt.as_deref());
        if ws.send(Message::Binary(frame.into())).await.is_err() {
            unregister_client(&shared, &input, id);
            return;
        }
    }
    let current = *level_rx.borrow_and_update();
    if current != levels::NOTHING && ws.send(level_frame(current)).await.is_err() {
        unregister_client(&shared, &input, id);
        return;
    }
    loop {
        tokio::select! {
            _ = stop.changed() => break,
            ev = event_rx.recv() => {
                // One-off events for the phone (a text field got focus).
                if let Ok(frame) = ev {
                    if ws.send(Message::Binary(frame.into())).await.is_err() { break; }
                }
            }
            changed = level_rx.changed() => {
                if changed.is_err() { break; }
                let v = *level_rx.borrow_and_update();
                if v != levels::NOTHING && ws.send(level_frame(v)).await.is_err() {
                    break;
                }
            }
            changed = led_rx.changed() => {
                if changed.is_err() { break; }
                let v = *led_rx.borrow_and_update();
                if v != leds::UNKNOWN
                    && ws.send(Message::Binary(vec![leds::FRAME_ID, v].into())).await.is_err()
                {
                    break;
                }
            }
            Some(frame) = voice_rx.recv() => {
                if ws.send(Message::Binary(frame.into())).await.is_err() { break; }
            }
            _ = tick.tick() => {
                if keepalives && last_rx.elapsed() > CLIENT_TIMEOUT {
                    shared.lock().unwrap().log(format!("Wi-Fi {label} stopped responding"));
                    break;
                }
                // Heartbeat: lets the phone notice if this link dies.
                if ws.send(Message::Binary(vec![leds::HEARTBEAT].into())).await.is_err() {
                    break;
                }
            }
            msg = ws.next() => match msg {
                Some(Ok(Message::Binary(data))) => {
                    last_rx = Instant::now();
                    if data.as_ref() == [KEEPALIVE] {
                        keepalives = true;
                    }
                    if !crate::media::handle(&data, &shared) && !voice.handle(&data) {
                        apply_bytes(&input, &data);
                    }
                }
                Some(Ok(_)) => last_rx = Instant::now(),
                _ => break,
            }
        }
    }
    unregister_client(&shared, &input, id);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener as StdListener;

    fn free_port() -> u16 {
        StdListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
    }

    fn wait(what: &str, cond: impl Fn() -> bool) {
        for _ in 0..100 {
            if cond() {
                return;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        panic!("timed out waiting for: {what}");
    }

    /// Starting needs /dev/uinput; where that is not allowed the tests cannot run.
    fn cannot_inject(server: &Server) -> bool {
        server.shared.lock().unwrap().error.as_deref().is_some_and(|e| e.contains("virtual input"))
    }

    #[test]
    fn a_busy_port_leaves_the_server_startable() {
        let port = free_port();
        let blocker = StdListener::bind(("0.0.0.0", port)).unwrap();
        let mut server = Server::new("tok".into());

        server.start(port);
        {
            let s = server.shared.lock().unwrap();
            assert!(!s.running);
            assert!(s.error.as_deref().unwrap().contains("already in use"), "{:?}", s.error);
            let holder = s.port_owner.as_ref().and_then(|o| o.pid);
            // (Wine, which the Windows tests also run under, reports every pid as 0.)
            assert!(holder == Some(std::process::id()) || (cfg!(windows) && holder == Some(0)), "names the holder: {holder:?}");
        }
        assert!(server.stop.is_none() && server.bt.is_none(), "nothing was half-started");

        // Free the port and press Start again: this used to silently do nothing.
        drop(blocker);
        server.start(port);
        if cannot_inject(&server) {
            eprintln!("no /dev/uinput access; skipping the rest");
            return;
        }
        assert!(server.shared.lock().unwrap().running, "Start works after the port was busy");
        assert!(server.shared.lock().unwrap().port_owner.is_none(), "the conflict is cleared");
        server.stop();
    }

    #[test]
    fn stop_really_frees_the_port_and_start_works_again() {
        let port = free_port();
        let mut server = Server::new("tok".into());
        server.start(port);
        if cannot_inject(&server) {
            return;
        }
        assert!(portowner::listener(port).is_some(), "listening");
        server.stop();
        assert!(!server.shared.lock().unwrap().running);
        assert!(StdListener::bind(("0.0.0.0", port)).is_ok(), "the port is free right after stop()");
        server.start(port);
        assert!(server.shared.lock().unwrap().running);
        server.stop();
    }

    #[test]
    fn reconnect_restarts_on_the_same_port() {
        let port = free_port();
        let mut server = Server::new("tok".into());
        server.start(port);
        if cannot_inject(&server) {
            return;
        }
        for round in 1..=3 {
            server.restart(port);
            wait("running again", || server.shared.lock().unwrap().running);
            let owner = portowner::listener(port).unwrap_or_else(|| panic!("not listening after restart {round}"));
            assert!(owner.pid == Some(std::process::id()) || (cfg!(windows) && owner.pid == Some(0)), "{:?}", owner.pid);
            assert!(server.shared.lock().unwrap().error.is_none(), "restart {round}");
        }
        server.stop();
    }

    async fn ws_connect(port: u16, token: &str) -> tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>> {
        let (mut ws, _) = tokio_tungstenite::connect_async(format!("ws://127.0.0.1:{port}")).await.unwrap();
        ws.send(Message::Text(token.into())).await.unwrap();
        match ws.next().await {
            Some(Ok(Message::Text(t))) => assert_eq!(t.as_str(), "ok"),
            other => panic!("expected ok, got {other:?}"),
        }
        ws
    }

    #[test]
    fn a_phone_on_the_cable_is_told_how_to_reach_the_computer_by_wifi_and_bluetooth() {
        let port = free_port();
        let mut server = Server::new("tok".into());
        server.start(port);
        if cannot_inject(&server) {
            return;
        }
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            // These test connections come from 127.0.0.1, like a phone behind adb's tunnel.
            let mut ws = ws_connect(port, "tok").await;
            let mut info = None;
            let end = Instant::now() + Duration::from_secs(3);
            while info.is_none() && Instant::now() < end {
                if let Ok(Some(Ok(Message::Binary(b)))) = tokio::time::timeout(Duration::from_millis(500), ws.next()).await {
                    if b.first() == Some(&crate::identity::INFO_FRAME) {
                        info = Some(String::from_utf8(b[1..].to_vec()).unwrap());
                    }
                }
            }
            let info = info.expect("the info frame arrives right after the connection is accepted");
            assert!(info.contains(&format!("port={port}")), "{info}");
            assert!(info.contains(&format!("id={}", crate::identity::computer_id())), "{info}");
            assert!(info.contains("name="), "{info}");
        });
        server.stop();
    }

    #[test]
    fn wifi_phones_get_a_heartbeat_and_silent_ones_are_dropped() {
        let port = free_port();
        let mut server = Server::new("tok".into());
        server.start(port);
        if cannot_inject(&server) {
            return;
        }
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            // A phone that sends keep-alives stays connected and receives heartbeats.
            let mut alive = ws_connect(port, "tok").await;
            let mut beats = 0;
            let end = Instant::now() + Duration::from_millis(3300);
            while Instant::now() < end {
                tokio::select! {
                    _ = tokio::time::sleep(Duration::from_millis(300)) => {
                        alive.send(Message::Binary(vec![0x00].into())).await.unwrap(); // keep-alive
                    }
                    m = alive.next() => match m {
                        Some(Ok(Message::Binary(b))) if b.as_ref() == [leds::HEARTBEAT] => beats += 1,
                        Some(Ok(_)) => {}
                        other => panic!("a phone sending keep-alives was dropped: {other:?}"),
                    }
                }
            }
            assert!(beats >= 2, "heartbeat about once a second, got {beats}");

            // A second phone that goes silent is dropped after the timeout.
            let mut silent = ws_connect(port, "tok").await;
            silent.send(Message::Binary(vec![KEEPALIVE].into())).await.unwrap(); // a current app
            let started = Instant::now();
            let ended = tokio::time::timeout(Duration::from_secs(6), async {
                loop {
                    match silent.next().await {
                        Some(Ok(_)) => continue, // heartbeats keep coming until it is dropped
                        _ => break,
                    }
                }
            })
            .await;
            assert!(ended.is_ok(), "the silent phone was never dropped");
            assert!(started.elapsed() < Duration::from_secs(5), "dropped within {:?}", started.elapsed());
        });
        assert!(
            server.shared.lock().unwrap().log.iter().any(|l| l.contains("stopped responding")),
            "the log says why"
        );
        server.stop();
    }

    #[test]
    fn an_older_wifi_app_without_keepalives_is_never_timed_out() {
        let port = free_port();
        let mut server = Server::new("tok".into());
        server.start(port);
        if cannot_inject(&server) {
            return;
        }
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let mut old = ws_connect(port, "tok").await;
            // Says nothing for three times the timeout, only reading (heartbeats arrive).
            let quiet = tokio::time::timeout(Duration::from_millis(3300), async {
                loop {
                    match old.next().await {
                        Some(Ok(_)) => continue,
                        other => return other.is_none() || other.is_some_and(|r| r.is_err()),
                    }
                }
            })
            .await;
            assert!(quiet.is_err(), "the older app was dropped while merely quiet");
            assert_eq!(server.shared.lock().unwrap().clients.len(), 1, "still registered");
        });
        server.stop();
    }

    #[cfg(unix)]
    #[test]
    fn voice_audio_over_wifi_comes_back_as_text_and_other_frames_still_work() {
        let port = free_port();
        let mut server = Server::new("tok".into());
        server.shared.lock().unwrap().voice = crate::voice::fake_engine();
        server.start(port);
        if cannot_inject(&server) {
            return;
        }
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let mut ws = ws_connect(port, "tok").await;
            ws.send(Message::Binary(vec![0x06, 1, 1].into())).await.unwrap(); // begin: command
            for _ in 0..40 {
                let mut f = vec![0x06, 2];
                f.extend_from_slice(&[1u8; 250]);
                ws.send(Message::Binary(f.into())).await.unwrap();
            }
            ws.send(Message::Binary(vec![0x06, 3].into())).await.unwrap(); // end
            let mut json = Vec::new();
            let end = Instant::now() + Duration::from_secs(10);
            while Instant::now() < end {
                if let Ok(Some(Ok(Message::Binary(b)))) = tokio::time::timeout(Duration::from_millis(500), ws.next()).await {
                    if b.first() == Some(&crate::voice::FRAME_OUT) {
                        json.extend_from_slice(&b[2..]);
                        if b[1] == 1 {
                            break;
                        }
                    }
                }
            }
            assert_eq!(String::from_utf8(json).unwrap(), r#"{"t":"text","text":"close this window","ms":1}"#);
        });
        server.stop();
    }
}
