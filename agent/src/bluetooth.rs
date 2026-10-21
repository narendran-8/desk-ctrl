//! Bluetooth transport: an RFCOMM (serial) service registered with BlueZ.
//!
//! The phone must already be paired with this PC. It connects to the service
//! UUID below; BlueZ hands us the connected socket through `Profile1.NewConnection`.
//! On the wire it is the same protocol as Wi-Fi, framed as `[len: u8][payload]`
//! because RFCOMM is a byte stream. The first frame is the pairing token; we
//! answer with a one-byte ACK frame so the phone knows it was accepted.

use crate::server::{self, SharedInput, SharedState, Transport};
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, OwnedFd, RawFd};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;
use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};

/// Must match the UUID in the phone app (android MainActivity.kt).
pub const SERVICE_UUID: &str = "c0de5c71-7e1a-4d1c-8d5e-d35c7c71a001";
const PROFILE_PATH: &str = "/dev/deskctrl/profile";
const ACK: u8 = 0x06;

#[derive(Default, Clone)]
pub struct BtStatus {
    /// Service registered with bluetoothd.
    pub registered: bool,
    /// Address of the first Bluetooth adapter, if there is one.
    pub adapter: Option<String>,
    pub powered: bool,
    /// RFCOMM channel the service was registered on.
    pub channel: Option<u8>,
    pub error: Option<String>,
}

impl BtStatus {
    pub fn summary(&self) -> String {
        if let Some(e) = &self.error {
            return e.clone();
        }
        match (&self.adapter, self.powered, self.registered) {
            (None, ..) => "No Bluetooth adapter available".into(),
            (Some(_), false, _) => "Bluetooth adapter is powered off".into(),
            (Some(_), true, false) => "Waiting for bluetoothd".into(),
            (Some(a), true, true) => match self.channel {
                Some(c) => format!("Ready (adapter {a}, channel {c})"),
                None => format!("Ready (adapter {a})"),
            },
        }
    }

    pub fn ready(&self) -> bool {
        self.error.is_none() && self.adapter.is_some() && self.powered && self.registered
    }
}

// ---- framing -------------------------------------------------------------

/// Read one frame. Zero-length frames are ignored (usable as keep-alives).
pub fn read_frame<R: Read>(r: &mut R) -> io::Result<Vec<u8>> {
    loop {
        let mut len = [0u8; 1];
        r.read_exact(&mut len)?;
        if len[0] == 0 {
            continue;
        }
        let mut buf = vec![0u8; len[0] as usize];
        r.read_exact(&mut buf)?;
        return Ok(buf);
    }
}

pub fn write_frame<W: Write>(w: &mut W, payload: &[u8]) -> io::Result<()> {
    assert!(!payload.is_empty() && payload.len() <= 255);
    let mut out = Vec::with_capacity(payload.len() + 1);
    out.push(payload.len() as u8);
    out.extend_from_slice(payload);
    w.write_all(&out)?;
    w.flush()
}

/// Drive one connected phone until it disconnects.
pub fn serve_stream<S: Read + Write>(mut s: S, addr: String, shared: &SharedState, input: &SharedInput) {
    let first = read_frame(&mut s);
    let why = match &first {
        Ok(f) if server::token_ok(shared, f) => None,
        Ok(_) => Some("wrong token".to_string()),
        // The phone connected but never sent its token (or the link broke straight away).
        Err(e) => Some(format!("no token received: {e}")),
    };
    if let Some(why) = why {
        shared.lock().unwrap().log(format!("Bluetooth {addr} rejected ({why})"));
        thread::sleep(server::BAD_TOKEN_DELAY);
        return;
    }
    if write_frame(&mut s, &[ACK]).is_err() {
        shared.lock().unwrap().log(format!("Bluetooth {addr}: could not send the reply"));
        return;
    }
    let label = addr.clone();
    let id = server::register_client(shared, Transport::Bluetooth, addr);
    // First heartbeat right away, so the phone knows this agent sends them (and can fail over fast).
    let _ = write_frame(&mut s, &[crate::leds::HEARTBEAT]);
    // Older apps send no keep-alives; for them silence is normal and they are never timed out.
    let mut keepalives = false;
    // Voice answers (see voice.rs) are written by this loop: the phone's keep-alive, once a
    // second, wakes it up if nothing else does.
    let (voice_tx, voice_rx) = std::sync::mpsc::channel::<Vec<u8>>();
    let voice_tx = Mutex::new(voice_tx);
    let engine = shared.lock().unwrap().voice.clone();
    let mut voice = crate::voice::VoiceSession::new(engine, Arc::new(move |f| drop(voice_tx.lock().unwrap().send(f))));
    loop {
        while let Ok(f) = voice_rx.try_recv() {
            if write_frame(&mut s, &f).is_err() {
                break;
            }
        }
        match read_frame(&mut s) {
            Ok(frame) => {
                if frame == [server::KEEPALIVE] {
                    keepalives = true;
                }
                if !voice.handle(&frame) {
                    server::apply_bytes(input, &frame);
                }
            }
            Err(e) if matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut) => {
                if keepalives {
                    // The app sends a keep-alive every second, so silence means the link is dead.
                    shared.lock().unwrap().log(format!("Bluetooth {label} stopped responding"));
                    break;
                }
            }
            Err(_) => break,
        }
    }
    server::unregister_client(shared, input, id);
}

/// Make reads on the socket give up after `timeout` instead of waiting forever.
fn set_recv_timeout(fd: RawFd, timeout: Duration) {
    let tv = libc::timeval {
        tv_sec: timeout.as_secs() as libc::time_t,
        tv_usec: timeout.subsec_micros() as libc::suseconds_t,
    };
    // SAFETY: setsockopt with a valid timeval on an fd we own.
    unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_RCVTIMEO,
            (&tv as *const libc::timeval).cast(),
            std::mem::size_of::<libc::timeval>() as libc::socklen_t,
        );
    }
}

/// Make a socket fd blocking again.
fn set_blocking(fd: RawFd) {
    // SAFETY: fcntl on an fd we own; only the O_NONBLOCK status flag is changed.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        if flags >= 0 && flags & libc::O_NONBLOCK != 0 {
            libc::fcntl(fd, libc::F_SETFL, flags & !libc::O_NONBLOCK);
        }
    }
}

// ---- BlueZ profile -------------------------------------------------------

type Conns = Arc<Mutex<Vec<(u64, RawFd)>>>;

struct Profile {
    shared: SharedState,
    input: SharedInput,
    conns: Conns,
    next: AtomicU64,
}

/// "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF" -> "AA:BB:CC:DD:EE:FF"
fn address_from_path(path: &str) -> String {
    path.rsplit('/')
        .next()
        .and_then(|s| s.strip_prefix("dev_"))
        .map(|s| s.replace('_', ":"))
        .unwrap_or_else(|| path.to_string())
}

#[zbus::interface(name = "org.bluez.Profile1")]
impl Profile {
    fn release(&self) {}

    fn request_disconnection(&self, _device: ObjectPath<'_>) {}

    fn new_connection(
        &self,
        device: ObjectPath<'_>,
        fd: zbus::zvariant::OwnedFd,
        _properties: HashMap<String, OwnedValue>,
    ) {
        let addr = address_from_path(device.as_str());
        let owned: OwnedFd = fd.into();
        let raw = owned.as_raw_fd();
        // BlueZ hands over its socket non-blocking; this thread reads with blocking
        // reads, which on a non-blocking socket fail at once and look like a bad token.
        set_blocking(raw);
        set_recv_timeout(raw, server::CLIENT_TIMEOUT);
        self.shared.lock().unwrap().log(format!("Bluetooth {addr}: phone connected, waiting for its token"));
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        self.conns.lock().unwrap().push((id, raw));
        let (shared, input, conns) = (self.shared.clone(), self.input.clone(), self.conns.clone());
        thread::spawn(move || {
            let file = File::from(owned);
            serve_stream(&file, addr, &shared, &input);
            // Forget the fd before closing it so stop() can never shut down a reused number.
            conns.lock().unwrap().retain(|c| c.0 != id);
            drop(file);
        });
    }
}

pub struct BtService {
    stop: Arc<AtomicBool>,
    conns: Conns,
    thread: Option<JoinHandle<()>>,
}

impl BtService {
    pub fn start(shared: SharedState, input: SharedInput) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let conns: Conns = Arc::new(Mutex::new(Vec::new()));
        let thread = {
            let (stop, conns) = (stop.clone(), conns.clone());
            thread::spawn(move || run(shared, input, conns, stop))
        };
        Self { stop, conns, thread: Some(thread) }
    }

    /// A handle that sends one frame to every connected phone (used for the lock-key lights).
    pub fn broadcaster(&self) -> impl Fn(&[u8]) + Send + 'static {
        let conns = self.conns.clone();
        move |payload: &[u8]| broadcast(&conns, payload)
    }

    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
        // Unblocks the reader threads of any connected phones.
        for (_, fd) in self.conns.lock().unwrap().iter() {
            unsafe { libc::shutdown(*fd, libc::SHUT_RDWR) };
        }
    }
}

/// Send one framed payload to every connected phone. Non-blocking: if a phone's
/// buffer is full the frame is dropped (the next update repairs it).
fn broadcast(conns: &Conns, payload: &[u8]) {
    let mut frame = Vec::with_capacity(payload.len() + 1);
    frame.push(payload.len() as u8);
    frame.extend_from_slice(payload);
    for (_, fd) in conns.lock().unwrap().iter() {
        unsafe {
            libc::send(*fd, frame.as_ptr().cast(), frame.len(), libc::MSG_NOSIGNAL | libc::MSG_DONTWAIT);
        }
    }
}

fn set_status(shared: &SharedState, f: impl FnOnce(&mut BtStatus)) {
    f(&mut shared.lock().unwrap().bt);
}

fn run(shared: SharedState, input: SharedInput, conns: Conns, stop: Arc<AtomicBool>) {
    let conn = match Connection::system() {
        Ok(c) => c,
        Err(e) => {
            set_status(&shared, |b| b.error = Some(format!("Bluetooth unavailable (no D-Bus): {e}")));
            return;
        }
    };
    let profile = Profile { shared: shared.clone(), input, conns, next: AtomicU64::new(1) };
    if let Err(e) = conn.object_server().at(PROFILE_PATH, profile) {
        set_status(&shared, |b| b.error = Some(format!("Bluetooth setup failed: {e}")));
        return;
    }

    let mut registered = false;
    while !stop.load(Ordering::Relaxed) {
        match bluez_state(&conn) {
            // bluetoothd is reachable (an adapter may or may not exist yet).
            Some(adapter) => {
                if !registered {
                    match register(&conn) {
                        Ok(channel) => {
                            registered = true;
                            set_status(&shared, |b| b.channel = Some(channel));
                            shared.lock().unwrap().log(format!("Bluetooth service registered (RFCOMM channel {channel})"));
                        }
                        Err(e) => set_status(&shared, |b| b.error = Some(format!("Bluetooth registration failed: {e}"))),
                    }
                }
                set_status(&shared, |b| {
                    b.adapter = adapter.as_ref().map(|a| a.0.clone());
                    b.powered = adapter.map_or(false, |a| a.1);
                    b.registered = registered;
                    if registered {
                        b.error = None;
                    }
                });
            }
            // bluetoothd restarted or is not running: register again when it returns.
            None => {
                registered = false;
                set_status(&shared, |b| {
                    b.adapter = None;
                    b.powered = false;
                    b.registered = false;
                    b.channel = None;
                    b.error = Some("bluetoothd is not running".into());
                });
            }
        }
        for _ in 0..15 {
            if stop.load(Ordering::Relaxed) {
                break;
            }
            thread::sleep(Duration::from_millis(200));
        }
    }

    if registered {
        let _ = unregister(&conn);
    }
    set_status(&shared, |b| *b = BtStatus::default());
}

fn profile_manager(conn: &Connection) -> zbus::Result<Proxy<'static>> {
    Proxy::new(conn, "org.bluez", "/org/bluez", "org.bluez.ProfileManager1")
}

/// RFCOMM channels to try, in order. A fixed channel plus an explicit service record
/// removes any guesswork about where the phone finds the service.
const CHANNELS: std::ops::RangeInclusive<u8> = 22..=30;

/// The SDP record: our UUID, reachable over L2CAP + RFCOMM on `channel`.
fn service_record(uuid: &str, channel: u8) -> String {
    format!(
        r#"<?xml version="1.0" encoding="UTF-8" ?>
<record>
  <attribute id="0x0001"><sequence><uuid value="{uuid}" /></sequence></attribute>
  <attribute id="0x0004"><sequence><sequence><uuid value="0x0100" /></sequence><sequence><uuid value="0x0003" /><uint8 value="0x{channel:02x}" /></sequence></sequence></attribute>
  <attribute id="0x0005"><sequence><uuid value="0x1002" /></sequence></attribute>
  <attribute id="0x0100"><text value="ViL" /></attribute>
</record>"#
    )
}

/// Register the service with BlueZ; returns the RFCOMM channel it ended up on.
fn register_profile(conn: &Connection, path: &str, uuid: &str) -> zbus::Result<u8> {
    let mut last = None;
    for channel in CHANNELS {
        let record = service_record(uuid, channel);
        let mut opts: HashMap<&str, Value<'_>> = HashMap::new();
        opts.insert("Name", Value::from("ViL"));
        opts.insert("Role", Value::from("server"));
        opts.insert("Channel", Value::from(channel as u16));
        opts.insert("ServiceRecord", Value::from(record.as_str()));
        // Only paired devices may connect; authorization would need a BlueZ agent to approve each one.
        opts.insert("RequireAuthentication", Value::from(true));
        opts.insert("RequireAuthorization", Value::from(false));
        match profile_manager(conn)?.call_method(
            "RegisterProfile",
            &(ObjectPath::try_from(path)?, uuid, opts),
        ) {
            Ok(_) => return Ok(channel),
            Err(e) => last = Some(e), // channel taken by another service: try the next one
        }
    }
    Err(last.expect("at least one channel was tried"))
}

fn register(conn: &Connection) -> zbus::Result<u8> {
    register_profile(conn, PROFILE_PATH, SERVICE_UUID)
}

fn unregister_profile(conn: &Connection, path: &str) -> zbus::Result<()> {
    profile_manager(conn)?.call_method("UnregisterProfile", &(ObjectPath::try_from(path)?,))?;
    Ok(())
}

fn unregister(conn: &Connection) -> zbus::Result<()> {
    unregister_profile(conn, PROFILE_PATH)
}

/// `None`: bluetoothd unreachable. `Some(None)`: running but no adapter.
/// `Some(Some((address, powered)))`: first adapter.
fn bluez_state(conn: &Connection) -> Option<Option<(String, bool)>> {
    type Objects = HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>;
    let om = Proxy::new(conn, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager").ok()?;
    let objs: Objects = om.call("GetManagedObjects", &()).ok()?;
    for ifaces in objs.values() {
        if let Some(a) = ifaces.get("org.bluez.Adapter1") {
            let addr = a.get("Address").and_then(|v| String::try_from(v.clone()).ok());
            let powered = a.get("Powered").and_then(|v| bool::try_from(v.clone()).ok()).unwrap_or(false);
            if let Some(addr) = addr {
                return Some(Some((addr, powered)));
            }
        }
    }
    Some(None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hid::Event;
    use crate::inject::{Input, Sink};
    use crate::server::Shared;
    use std::os::unix::net::UnixStream;

    #[derive(Clone, Default)]
    struct Recorder(Arc<Mutex<Vec<String>>>);
    impl Sink for Recorder {
        fn apply(&mut self, ev: Event) -> io::Result<()> {
            self.0.lock().unwrap().push(format!("{ev:?}"));
            Ok(())
        }
    }

    fn setup(token: &str) -> (SharedState, SharedInput, Recorder) {
        let rec = Recorder::default();
        let shared = Arc::new(Mutex::new(Shared { token: token.into(), ..Default::default() }));
        let input = Arc::new(Mutex::new(Input::new(Box::new(rec.clone()))));
        (shared, input, rec)
    }

    #[test]
    fn address_from_bluez_path() {
        assert_eq!(address_from_path("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"), "AA:BB:CC:DD:EE:FF");
    }

    #[test]
    fn frames_round_trip_and_skip_keepalives() {
        let mut buf = Vec::new();
        write_frame(&mut buf, &[1, 2, 3]).unwrap();
        buf.push(0); // keep-alive
        write_frame(&mut buf, &[9]).unwrap();
        let mut r = &buf[..];
        assert_eq!(read_frame(&mut r).unwrap(), vec![1, 2, 3]);
        assert_eq!(read_frame(&mut r).unwrap(), vec![9]);
        assert!(read_frame(&mut r).is_err());
    }

    #[test]
    fn good_token_is_acked_and_events_reach_the_sink() {
        let (shared, input, rec) = setup("abcd1234");
        let (mut phone, agent) = UnixStream::pair().unwrap();
        let t = {
            let (s, i) = (shared.clone(), input.clone());
            thread::spawn(move || serve_stream(agent, "AA:BB".into(), &s, &i))
        };
        write_frame(&mut phone, b"abcd1234").unwrap();
        assert_eq!(read_frame(&mut phone).unwrap(), vec![ACK]);
        write_frame(&mut phone, &[0x01, 0x00, 0x04]).unwrap(); // key A down
        write_frame(&mut phone, &[0x03, 0x00, 0x05, 0xFF, 0xFE]).unwrap(); // move (5, -2)
        // Disconnect with the key still held: it must be released.
        drop(phone);
        t.join().unwrap();

        let ev = rec.0.lock().unwrap().clone();
        assert_eq!(ev[0], "Key { hid: 4, down: true }");
        assert_eq!(ev[1], "Move { dx: 5, dy: -2 }");
        assert_eq!(ev[2], "Key { hid: 4, down: false }", "held key released on disconnect");
        assert!(shared.lock().unwrap().clients.is_empty());
    }

    #[test]
    fn held_key_survives_while_another_link_is_still_connected() {
        let (shared, input, rec) = setup("tok");
        let wifi = server::register_client(&shared, Transport::WiFi, "10.0.0.2".into());
        let (mut phone, agent) = UnixStream::pair().unwrap();
        let t = {
            let (s, i) = (shared.clone(), input.clone());
            thread::spawn(move || serve_stream(agent, "AA:BB".into(), &s, &i))
        };
        write_frame(&mut phone, b"tok").unwrap();
        read_frame(&mut phone).unwrap();
        write_frame(&mut phone, &[0x01, 0x00, 0x04]).unwrap();
        drop(phone); // Bluetooth drops, Wi-Fi still up
        t.join().unwrap();
        assert_eq!(rec.0.lock().unwrap().len(), 1, "no release while Wi-Fi is connected");

        server::unregister_client(&shared, &input, wifi); // last link gone
        assert_eq!(rec.0.lock().unwrap().last().unwrap(), "Key { hid: 4, down: false }");
    }

    #[test]
    fn bad_token_is_rejected_without_ack() {
        let (shared, input, rec) = setup("right");
        let (mut phone, agent) = UnixStream::pair().unwrap();
        let t = {
            let (s, i) = (shared.clone(), input.clone());
            thread::spawn(move || serve_stream(agent, "AA:BB".into(), &s, &i))
        };
        write_frame(&mut phone, b"wrong").unwrap();
        t.join().unwrap();
        assert!(read_frame(&mut phone).is_err(), "connection closed with no ACK");
        assert!(shared.lock().unwrap().clients.is_empty());
        assert!(rec.0.lock().unwrap().is_empty());
    }

    /// Exercises the real zbus path BlueZ uses: a D-Bus call carrying a socket fd.
    #[test]
    fn new_connection_over_dbus_hands_the_fd_to_serve_stream() {
        dbus_handover(false);
    }

    /// BlueZ passes its Bluetooth socket non-blocking. A phone that sends its token a
    /// moment after connecting must still be accepted (a blocking read on a
    /// non-blocking socket fails at once with "would block").
    #[test]
    fn a_non_blocking_socket_from_bluez_still_works() {
        dbus_handover(true);
    }

    fn dbus_handover(nonblocking: bool) {
        let Ok(server) = Connection::session() else {
            eprintln!("no D-Bus session bus; skipping");
            return;
        };
        let (shared, input, rec) = setup("tok");
        let conns: Conns = Default::default();
        let profile = Profile {
            shared: shared.clone(),
            input: input.clone(),
            conns: conns.clone(),
            next: AtomicU64::new(1),
        };
        server.object_server().at("/test/profile", profile).unwrap();
        let dest = server.unique_name().unwrap().to_string();

        let caller = Connection::session().unwrap();
        let (mut phone, agent) = UnixStream::pair().unwrap();
        if nonblocking {
            agent.set_nonblocking(true).unwrap();
        }
        let fd: zbus::zvariant::OwnedFd = OwnedFd::from(agent).into();
        let props: HashMap<String, OwnedValue> = HashMap::new();
        Proxy::new(&caller, dest.as_str(), "/test/profile", "org.bluez.Profile1")
            .unwrap()
            .call_method(
                "NewConnection",
                &(ObjectPath::try_from("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF").unwrap(), fd, props),
            )
            .unwrap();

        thread::sleep(Duration::from_millis(150)); // the agent thread is already reading
        write_frame(&mut phone, b"tok").unwrap();
        assert_eq!(read_frame(&mut phone).unwrap(), vec![ACK], "nonblocking={nonblocking}");
        write_frame(&mut phone, &[0x01, 0x00, 0x04]).unwrap();
        wait_for(|| rec.0.lock().unwrap().len() == 1);
        {
            let s = shared.lock().unwrap();
            assert_eq!(s.clients.len(), 1);
            assert_eq!(s.clients[0].addr, "AA:BB:CC:DD:EE:FF");
            assert_eq!(s.clients[0].transport, Transport::Bluetooth);
        }

        // What BtService::stop() does: shut the socket down, the reader thread must wind up.
        for (_, fd) in conns.lock().unwrap().iter() {
            unsafe { libc::shutdown(*fd, libc::SHUT_RDWR) };
        }
        wait_for(|| shared.lock().unwrap().clients.is_empty());
        wait_for(|| conns.lock().unwrap().is_empty());
        assert_eq!(rec.0.lock().unwrap().last().unwrap(), "Key { hid: 4, down: false }");
    }

    #[test]
    fn broadcast_reaches_every_connected_phone() {
        let conns: Conns = Default::default();
        let (mut a, a_agent) = UnixStream::pair().unwrap();
        let (mut b, b_agent) = UnixStream::pair().unwrap();
        conns.lock().unwrap().push((1, a_agent.as_raw_fd()));
        conns.lock().unwrap().push((2, b_agent.as_raw_fd()));

        broadcast(&conns, &[0x10, 0x01]);

        assert_eq!(read_frame(&mut a).unwrap(), vec![0x10, 0x01]);
        assert_eq!(read_frame(&mut b).unwrap(), vec![0x10, 0x01]);
    }

    fn wait_for(cond: impl Fn() -> bool) {
        for _ in 0..100 {
            if cond() {
                return;
            }
            thread::sleep(Duration::from_millis(50));
        }
        panic!("condition not met within 5s");
    }

    #[test]
    fn service_record_names_our_uuid_and_the_rfcomm_channel() {
        let r = service_record(SERVICE_UUID, 22);
        assert!(r.contains(&format!("<uuid value=\"{SERVICE_UUID}\" />")), "service class = our UUID");
        assert!(r.contains("<uuid value=\"0x0003\" /><uint8 value=\"0x16\" />"), "RFCOMM on channel 22 (0x16)");
        assert!(r.contains("0x1002"), "listed in the public browse group");
        assert!(service_record(SERVICE_UUID, 30).contains("0x1e"));
    }

    /// The real bluetoothd must accept the record and a fixed channel. Uses its own
    /// UUID and path, so a running agent is not affected.
    #[test]
    fn bluez_accepts_the_service_record_and_a_fixed_channel() {
        const PATH: &str = "/dev/deskctrl/test_profile";
        const UUID: &str = "c0de5c71-7e1a-4d1c-8d5e-d35c7c71ffff";
        let Ok(conn) = Connection::system() else {
            eprintln!("no system bus; skipping");
            return;
        };
        let (shared, input, _rec) = setup("tok");
        let profile = Profile { shared, input, conns: Default::default(), next: AtomicU64::new(1) };
        conn.object_server().at(PATH, profile).unwrap();
        match register_profile(&conn, PATH, UUID) {
            Ok(channel) => {
                assert!(CHANNELS.contains(&channel), "registered on channel {channel}");
                unregister_profile(&conn, PATH).expect("unregisters again");
            }
            Err(e) if e.to_string().contains("ServiceUnknown") || e.to_string().contains("NameHasNoOwner") => {
                eprintln!("bluetoothd not running; skipping");
            }
            Err(e) => panic!("BlueZ rejected the registration: {e}"),
        }
    }

    /// A phone that stops sending (out of range, Bluetooth switched off) must be dropped
    /// after the timeout, so the phone can fail over and held keys are released.
    #[test]
    fn a_silent_bluetooth_phone_is_dropped() {
        let Ok(server) = Connection::session() else {
            eprintln!("no D-Bus session bus; skipping");
            return;
        };
        let (shared, input, rec) = setup("tok");
        let profile = Profile {
            shared: shared.clone(),
            input: input.clone(),
            conns: Default::default(),
            next: AtomicU64::new(1),
        };
        server.object_server().at("/test/silent", profile).unwrap();
        let dest = server.unique_name().unwrap().to_string();
        let caller = Connection::session().unwrap();
        let (mut phone, agent) = UnixStream::pair().unwrap();
        phone.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
        let fd: zbus::zvariant::OwnedFd = OwnedFd::from(agent).into();
        let props: HashMap<String, OwnedValue> = HashMap::new();
        Proxy::new(&caller, dest.as_str(), "/test/silent", "org.bluez.Profile1")
            .unwrap()
            .call_method(
                "NewConnection",
                &(ObjectPath::try_from("/org/bluez/hci0/dev_11_22_33_44_55_66").unwrap(), fd, props),
            )
            .unwrap();
        write_frame(&mut phone, b"tok").unwrap();
        assert_eq!(read_frame(&mut phone).unwrap(), vec![ACK]);
        write_frame(&mut phone, &[0x00]).unwrap(); // the app's keep-alive: this phone is timed out when silent
        write_frame(&mut phone, &[0x01, 0x00, 0x04]).unwrap(); // key A down ...
        wait_for(|| shared.lock().unwrap().clients.len() == 1);

        // ... then silence. After CLIENT_TIMEOUT the agent drops the phone and releases the key.
        let started = std::time::Instant::now();
        while read_frame(&mut phone).is_ok() {} // (the agent's first heartbeat arrives first)
        // read_frame failed: the agent closed the silent connection
        assert!(started.elapsed() < Duration::from_secs(5), "dropped within the timeout, took {:?}", started.elapsed());
        wait_for(|| shared.lock().unwrap().clients.is_empty());
        assert_eq!(rec.0.lock().unwrap().last().unwrap(), "Key { hid: 4, down: false }", "held key released");
        assert!(shared.lock().unwrap().log.iter().any(|l| l.contains("stopped responding")));
    }

    /// Keep-alives (what the app sends every second) keep a quiet phone connected.
    #[test]
    fn keepalives_keep_a_quiet_bluetooth_phone_connected() {
        let Ok(server) = Connection::session() else {
            return;
        };
        let (shared, input, _rec) = setup("tok");
        let profile = Profile { shared: shared.clone(), input, conns: Default::default(), next: AtomicU64::new(1) };
        server.object_server().at("/test/alive", profile).unwrap();
        let dest = server.unique_name().unwrap().to_string();
        let caller = Connection::session().unwrap();
        let (mut phone, agent) = UnixStream::pair().unwrap();
        let fd: zbus::zvariant::OwnedFd = OwnedFd::from(agent).into();
        let props: HashMap<String, OwnedValue> = HashMap::new();
        Proxy::new(&caller, dest.as_str(), "/test/alive", "org.bluez.Profile1")
            .unwrap()
            .call_method(
                "NewConnection",
                &(ObjectPath::try_from("/org/bluez/hci0/dev_11_22_33_44_55_77").unwrap(), fd, props),
            )
            .unwrap();
        write_frame(&mut phone, b"tok").unwrap();
        assert_eq!(read_frame(&mut phone).unwrap(), vec![ACK]);
        for _ in 0..8 {
            thread::sleep(Duration::from_millis(400)); // 3.2 s in total, three times the timeout
            write_frame(&mut phone, &[0x00]).unwrap(); // keep-alive
        }
        assert_eq!(shared.lock().unwrap().clients.len(), 1, "still connected");
    }

    /// An older app never sends keep-alives; going quiet must not get it dropped.
    #[test]
    fn an_older_app_without_keepalives_is_never_timed_out() {
        let Ok(server) = Connection::session() else {
            return;
        };
        let (shared, input, _rec) = setup("tok");
        let profile = Profile { shared: shared.clone(), input, conns: Default::default(), next: AtomicU64::new(1) };
        server.object_server().at("/test/older", profile).unwrap();
        let dest = server.unique_name().unwrap().to_string();
        let caller = Connection::session().unwrap();
        let (mut phone, agent) = UnixStream::pair().unwrap();
        let fd: zbus::zvariant::OwnedFd = OwnedFd::from(agent).into();
        let props: HashMap<String, OwnedValue> = HashMap::new();
        Proxy::new(&caller, dest.as_str(), "/test/older", "org.bluez.Profile1")
            .unwrap()
            .call_method(
                "NewConnection",
                &(ObjectPath::try_from("/org/bluez/hci0/dev_11_22_33_44_55_88").unwrap(), fd, props),
            )
            .unwrap();
        write_frame(&mut phone, b"tok").unwrap();
        assert_eq!(read_frame(&mut phone).unwrap(), vec![ACK]);
        thread::sleep(Duration::from_millis(3200)); // three times the timeout, saying nothing
        assert_eq!(shared.lock().unwrap().clients.len(), 1, "still connected");
        write_frame(&mut phone, &[0x03, 0, 1, 0, 1]).unwrap(); // and still works afterwards
    }

    #[test]
    fn the_first_heartbeat_follows_the_ack_immediately() {
        let (shared, input, _rec) = setup("tok");
        let (mut phone, agent) = UnixStream::pair().unwrap();
        let t = thread::spawn(move || serve_stream(agent, "AA:BB".into(), &shared, &input));
        write_frame(&mut phone, b"tok").unwrap();
        assert_eq!(read_frame(&mut phone).unwrap(), vec![ACK]);
        assert_eq!(read_frame(&mut phone).unwrap(), vec![crate::leds::HEARTBEAT]);
        drop(phone);
        t.join().unwrap();
    }

    #[test]
    fn voice_audio_over_bluetooth_comes_back_as_text() {
        let (shared, input, _rec) = setup("tok");
        shared.lock().unwrap().voice = crate::voice::fake_engine();
        let (mut phone, agent) = UnixStream::pair().unwrap();
        let t = thread::spawn(move || serve_stream(agent, "AA:BB".into(), &shared, &input));
        write_frame(&mut phone, b"tok").unwrap();
        assert_eq!(read_frame(&mut phone).unwrap(), vec![ACK]);
        assert_eq!(read_frame(&mut phone).unwrap(), vec![crate::leds::HEARTBEAT]);
        write_frame(&mut phone, &[0x06, 1, 0]).unwrap(); // begin: dictate
        for _ in 0..40 {
            let mut f = vec![0x06, 2];
            f.extend_from_slice(&[1u8; 250]); // 40 x 250 bytes = 0.3 s
            write_frame(&mut phone, &f).unwrap();
        }
        write_frame(&mut phone, &[0x06, 3]).unwrap(); // end
        // The answer is written when the agent's loop next wakes: the phone's keep-alive does that.
        phone.set_read_timeout(Some(Duration::from_millis(200))).unwrap();
        let mut json = Vec::new();
        for _ in 0..50 {
            let _ = write_frame(&mut phone, &[0x00]);
            match read_frame(&mut phone) {
                Ok(f) if f[0] == crate::voice::FRAME_OUT => {
                    json.extend_from_slice(&f[2..]);
                    if f[1] == 1 {
                        break;
                    }
                }
                _ => {}
            }
        }
        assert_eq!(String::from_utf8(json).unwrap(), r#"{"t":"text","text":"hello world","ms":1}"#);
        drop(phone);
        t.join().unwrap();
    }
}
