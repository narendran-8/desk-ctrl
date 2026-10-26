//! Remote desktop-audio service.
//!
//! It intentionally uses a separate authenticated WebSocket (`/audio/v1`).  Audio frames are
//! bounded and disposable; input frames continue on `/` even if a receiver is slow.

use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::net::TcpStream;
use tokio::sync::{mpsc as async_mpsc, watch};
use tokio_tungstenite::{WebSocketStream, tungstenite::Message};

use crate::server::SharedState;

pub const PATH: &str = "/audio/v1";
pub const PROTOCOL: u8 = 1;
pub const DATA: u8 = 1;
pub const RATE: u32 = 48_000;
pub const CHANNELS: u8 = 2;
pub const FRAME_MS: usize = 20;
pub const SAMPLES_PER_FRAME: usize = RATE as usize * FRAME_MS / 1000;
pub const PCM_BYTES: usize = SAMPLES_PER_FRAME * CHANNELS as usize * 2;
pub const HEADER_BYTES: usize = 16;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OutputDevice {
    pub id: String,
    pub label: String,
}

fn packet(seq: u32, pcm: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER_BYTES + pcm.len());
    out.extend_from_slice(&[DATA, PROTOCOL, CHANNELS, 1]); // 1 = signed little-endian PCM16
    out.extend_from_slice(&RATE.to_le_bytes());
    out.extend_from_slice(&seq.to_le_bytes());
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u32;
    out.extend_from_slice(&millis.to_le_bytes());
    out.extend_from_slice(pcm);
    out
}

pub fn valid_packet(data: &[u8]) -> bool {
    data.len() >= HEADER_BYTES
        && data[0] == DATA
        && data[1] == PROTOCOL
        && data[2] == CHANNELS
        && data[3] == 1
        && u32::from_le_bytes(data[4..8].try_into().unwrap()) == RATE
        && (data.len() - HEADER_BYTES).is_multiple_of(2)
}

fn reply(op: &str, extra: Value) -> Message {
    let mut value = json!({"op": op, "version": PROTOCOL});
    if let (Some(base), Some(fields)) = (value.as_object_mut(), extra.as_object()) {
        base.extend(fields.clone());
    }
    Message::Text(value.to_string().into())
}

fn error(message: impl Into<String>) -> Message {
    reply("error", json!({"message": message.into()}))
}

pub async fn handle(
    mut ws: WebSocketStream<TcpStream>,
    shared: SharedState,
    mut stop: watch::Receiver<bool>,
) {
    let Some(Ok(Message::Text(first))) = ws.next().await else {
        return;
    };
    let Ok(command) = serde_json::from_str::<Value>(&first) else {
        let _ = ws.send(error("Invalid audio command")).await;
        return;
    };
    match command["op"].as_str() {
        Some("discover") => {
            let outputs = platform::outputs().unwrap_or_default();
            let body = json!({
                "computerId": crate::identity::computer_id(),
                "name": crate::usb::computer_name(),
                "capture": platform::capture_available(),
                "outputs": outputs.into_iter().map(|d| json!({"id": d.id, "label": d.label})).collect::<Vec<_>>(),
            });
            let _ = ws.send(reply("devices", body)).await;
        }
        Some("source") => {
            let play_source = command["playSource"].as_bool().unwrap_or(false);
            let (tx, mut rx) = async_mpsc::channel::<Vec<u8>>(8);
            let mut source = match platform::Capture::start(play_source, tx) {
                Ok(source) => source,
                Err(e) => {
                    let _ = ws.send(error(e)).await;
                    return;
                }
            };
            let _ = ws
                .send(reply(
                    "active",
                    json!({"role":"source","rate":RATE,"channels":CHANNELS}),
                ))
                .await;
            loop {
                tokio::select! {
                    _ = stop.changed() => break,
                    frame = rx.recv() => match frame {
                        Some(frame) => if ws.send(Message::Binary(frame.into())).await.is_err() { break; },
                        None => break,
                    },
                    incoming = ws.next() => match incoming {
                        Some(Ok(Message::Text(t))) if serde_json::from_str::<Value>(&t).ok().and_then(|v| v["op"].as_str().map(str::to_owned)).as_deref() == Some("stop") => break,
                        Some(Ok(Message::Ping(p))) => if ws.send(Message::Pong(p)).await.is_err() { break; },
                        Some(Ok(_)) => {},
                        _ => break,
                    }
                }
            }
            source.stop();
        }
        Some("sink") => {
            let device = command["device"].as_str().unwrap_or("default");
            let mut sink = match platform::Playback::start(device) {
                Ok(sink) => sink,
                Err(e) => {
                    let _ = ws.send(error(e)).await;
                    return;
                }
            };
            let _ = ws
                .send(reply("active", json!({"role":"sink","device":device})))
                .await;
            loop {
                tokio::select! {
                    _ = stop.changed() => break,
                    incoming = ws.next() => match incoming {
                        Some(Ok(Message::Binary(data))) if valid_packet(&data) => {
                            if !sink.write(data[HEADER_BYTES..].to_vec()) {
                                let _ = ws.send(error("The selected audio output became unavailable")).await;
                                break;
                            }
                        },
                        Some(Ok(Message::Text(t))) => {
                            if let Ok(v) = serde_json::from_str::<Value>(&t) {
                                match v["op"].as_str() {
                                    Some("gain") => sink.gain(v["volume"].as_f64().unwrap_or(1.0) as f32, v["muted"].as_bool().unwrap_or(false)),
                                    Some("stop") => break,
                                    _ => {}
                                }
                            }
                        }
                        Some(Ok(Message::Ping(p))) => if ws.send(Message::Pong(p)).await.is_err() { break; },
                        Some(Ok(_)) => {},
                        _ => break,
                    }
                }
            }
            sink.stop();
        }
        _ => {
            let _ = ws.send(error("Unknown audio operation")).await;
        }
    }
    shared.lock().unwrap().log("Audio session ended");
}

#[cfg(unix)]
mod platform {
    use super::*;
    use std::io::{Read, Write};
    use std::process::{Child, ChildStdin, Command, Stdio};
    use std::sync::mpsc::{self, SyncSender, TrySendError};
    use std::thread::JoinHandle;

    fn run(args: &[&str]) -> Result<String, String> {
        let output = Command::new("pactl")
            .args(args)
            .output()
            .map_err(|e| format!("PulseAudio/PipeWire is unavailable: {e}"))?;
        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
        }
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }

    pub fn outputs() -> Result<Vec<OutputDevice>, String> {
        let text = run(&["list", "short", "sinks"])?;
        let mut out = vec![OutputDevice {
            id: "default".into(),
            label: "System default".into(),
        }];
        for line in text.lines() {
            let mut columns = line.split_whitespace();
            let _index = columns.next();
            if let Some(name) = columns.next() {
                out.push(OutputDevice {
                    id: name.into(),
                    label: name.replace(['_', '.'], " "),
                });
            }
        }
        Ok(out)
    }

    pub fn capture_available() -> bool {
        Command::new("parec")
            .arg("--help")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok()
    }

    struct RouteGuard {
        module: Option<String>,
        previous_default: Option<String>,
        previous_inputs: Vec<(String, String)>,
    }

    impl RouteGuard {
        fn prepare(play_source: bool) -> Result<(Self, String), String> {
            let default = run(&["get-default-sink"])?;
            if play_source {
                return Ok((
                    Self {
                        module: None,
                        previous_default: None,
                        previous_inputs: vec![],
                    },
                    format!("{default}.monitor"),
                ));
            }
            let sink = format!("vil_remote_{}", std::process::id());
            let module = run(&[
                "load-module",
                "module-null-sink",
                &format!("sink_name={sink}"),
                "sink_properties=device.description=ViL_Remote_Audio",
                "rate=48000",
                "channels=2",
            ])?;
            let mut previous_inputs: Vec<(String, String)> = Vec::new();
            if let Ok(inputs) = run(&["list", "short", "sink-inputs"]) {
                for line in inputs.lines() {
                    let columns: Vec<_> = line.split_whitespace().collect();
                    if columns.len() >= 2 {
                        previous_inputs.push((columns[0].to_string(), columns[1].to_string()));
                    }
                }
            }
            if let Err(e) = run(&["set-default-sink", &sink]) {
                let _ = run(&["unload-module", &module]);
                return Err(e);
            }
            for (id, _) in &previous_inputs {
                let _ = run(&["move-sink-input", id, &sink]);
            }
            Ok((
                Self {
                    module: Some(module),
                    previous_default: Some(default),
                    previous_inputs,
                },
                format!("{sink}.monitor"),
            ))
        }
    }

    impl Drop for RouteGuard {
        fn drop(&mut self) {
            if let Some(default) = &self.previous_default {
                let _ = run(&["set-default-sink", default]);
                for (id, old) in &self.previous_inputs {
                    let _ = run(&["move-sink-input", id, old]);
                }
            }
            if let Some(module) = &self.module {
                let _ = run(&["unload-module", module]);
            }
        }
    }

    pub struct Capture {
        child: Child,
        thread: Option<JoinHandle<()>>,
        _route: RouteGuard,
    }

    impl Capture {
        pub fn start(play_source: bool, tx: async_mpsc::Sender<Vec<u8>>) -> Result<Self, String> {
            let (route, monitor) = RouteGuard::prepare(play_source)?;
            let mut child = Command::new("parec")
                .args([
                    "--raw",
                    "--format=s16le",
                    "--rate=48000",
                    "--channels=2",
                    "--latency-msec=40",
                    "--process-time-msec=10",
                    &format!("--device={monitor}"),
                ])
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|e| format!("Cannot capture desktop audio: {e}"))?;
            let mut stdout = child.stdout.take().ok_or("Cannot read desktop audio")?;
            let thread = std::thread::spawn(move || {
                let mut seq = 0u32;
                loop {
                    let mut pcm = vec![0u8; PCM_BYTES];
                    if stdout.read_exact(&mut pcm).is_err() {
                        break;
                    }
                    match tx.try_send(packet(seq, &pcm)) {
                        Ok(()) | Err(async_mpsc::error::TrySendError::Full(_)) => {}
                        Err(async_mpsc::error::TrySendError::Closed(_)) => break,
                    }
                    seq = seq.wrapping_add(1);
                }
            });
            Ok(Self {
                child,
                thread: Some(thread),
                _route: route,
            })
        }
        pub fn stop(&mut self) {
            let _ = self.child.kill();
            let _ = self.child.wait();
            if let Some(thread) = self.thread.take() {
                let _ = thread.join();
            }
        }
    }

    pub struct Playback {
        child: Child,
        tx: Option<SyncSender<Vec<u8>>>,
        gain: std::sync::Arc<std::sync::Mutex<(f32, bool)>>,
        thread: Option<JoinHandle<()>>,
    }

    impl Playback {
        pub fn start(device: &str) -> Result<Self, String> {
            let mut cmd = Command::new("pacat");
            cmd.args([
                "--playback",
                "--raw",
                "--format=s16le",
                "--rate=48000",
                "--channels=2",
                "--latency-msec=40",
                "--process-time-msec=10",
            ]);
            if device != "default" {
                cmd.arg(format!("--device={device}"));
            }
            let mut child = cmd
                .stdin(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|e| format!("Cannot play remote audio: {e}"))?;
            let stdin = child.stdin.take().ok_or("Cannot open audio output")?;
            let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(8);
            let gain = std::sync::Arc::new(std::sync::Mutex::new((1.0, false)));
            let copy = gain.clone();
            let thread = std::thread::spawn(move || playback_writer(stdin, rx, copy));
            Ok(Self {
                child,
                tx: Some(tx),
                gain,
                thread: Some(thread),
            })
        }
        pub fn write(&mut self, pcm: Vec<u8>) -> bool {
            if self.child.try_wait().ok().flatten().is_some() {
                return false;
            }
            match self.tx.as_ref().map(|tx| tx.try_send(pcm)) {
                Some(Ok(())) | Some(Err(TrySendError::Full(_))) => true,
                _ => false,
            }
        }
        pub fn gain(&mut self, volume: f32, muted: bool) {
            *self.gain.lock().unwrap() = (volume.clamp(0.0, 1.0), muted);
        }
        pub fn stop(&mut self) {
            self.tx.take();
            let _ = self.child.kill();
            let _ = self.child.wait();
            if let Some(thread) = self.thread.take() {
                let _ = thread.join();
            }
        }
    }

    fn playback_writer(
        mut stdin: ChildStdin,
        rx: mpsc::Receiver<Vec<u8>>,
        gain: std::sync::Arc<std::sync::Mutex<(f32, bool)>>,
    ) {
        for mut pcm in rx {
            let (volume, muted) = *gain.lock().unwrap();
            if muted || volume < 0.999 {
                for bytes in pcm.chunks_exact_mut(2) {
                    let sample = i16::from_le_bytes([bytes[0], bytes[1]]);
                    let scaled = if muted {
                        0
                    } else {
                        (sample as f32 * volume) as i16
                    };
                    bytes.copy_from_slice(&scaled.to_le_bytes());
                }
            }
            if stdin.write_all(&pcm).is_err() {
                break;
            }
        }
    }
}

#[cfg(windows)]
mod platform {
    use super::*;
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use cpal::{SampleFormat, StreamConfig};
    use std::collections::VecDeque;
    use std::sync::{Arc, Mutex};

    fn host() -> cpal::Host {
        cpal::default_host()
    }
    pub fn capture_available() -> bool {
        host().default_output_device().is_some()
    }
    pub fn outputs() -> Result<Vec<OutputDevice>, String> {
        let h = host();
        let default = h.default_output_device().and_then(|d| d.name().ok());
        let mut out = vec![OutputDevice {
            id: "default".into(),
            label: default
                .map(|n| format!("System default — {n}"))
                .unwrap_or_else(|| "System default".into()),
        }];
        for d in h.output_devices().map_err(|e| e.to_string())? {
            if let Ok(name) = d.name() {
                out.push(OutputDevice {
                    id: name.clone(),
                    label: name,
                });
            }
        }
        Ok(out)
    }

    fn output(id: &str) -> Result<cpal::Device, String> {
        let h = host();
        if id == "default" {
            return h.default_output_device().ok_or("No output device".into());
        }
        h.output_devices()
            .map_err(|e| e.to_string())?
            .find(|d| d.name().ok().as_deref() == Some(id))
            .ok_or_else(|| "The selected output is unavailable".into())
    }

    pub struct Capture {
        _stream: cpal::Stream,
    }
    impl Capture {
        pub fn start(play_source: bool, tx: async_mpsc::Sender<Vec<u8>>) -> Result<Self, String> {
            if !play_source {
                return Err("Windows cannot mute the source safely yet. Enable ‘Also play on source’ to start.".into());
            }
            let device = output("default")?;
            let supported = device.default_output_config().map_err(|e| e.to_string())?;
            let config = StreamConfig {
                channels: CHANNELS as u16,
                sample_rate: cpal::SampleRate(RATE),
                buffer_size: cpal::BufferSize::Default,
            };
            let pending = Arc::new(Mutex::new(Vec::<i16>::new()));
            let error = |e| eprintln!("audio capture error: {e}");
            let stream = match supported.sample_format() {
                SampleFormat::I16 => {
                    let pending = pending.clone();
                    let tx = tx.clone();
                    device.build_input_stream(
                        &config,
                        move |data: &[i16], _| push_samples(data.iter().copied(), &pending, &tx),
                        error,
                        None,
                    )
                }
                SampleFormat::F32 => {
                    let pending = pending.clone();
                    let tx = tx.clone();
                    device.build_input_stream(
                        &config,
                        move |data: &[f32], _| {
                            push_samples(
                                data.iter()
                                    .map(|s| (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16),
                                &pending,
                                &tx,
                            )
                        },
                        error,
                        None,
                    )
                }
                other => return Err(format!("Unsupported Windows capture format: {other:?}")),
            }
            .map_err(|e| format!("Cannot open Windows loopback capture: {e}"))?;
            stream.play().map_err(|e| e.to_string())?;
            Ok(Self { _stream: stream })
        }
        pub fn stop(&mut self) {}
    }

    fn push_samples(
        samples: impl Iterator<Item = i16>,
        pending: &Arc<Mutex<Vec<i16>>>,
        tx: &async_mpsc::Sender<Vec<u8>>,
    ) {
        let mut p = pending.lock().unwrap();
        p.extend(samples);
        while p.len() >= SAMPLES_PER_FRAME * CHANNELS as usize {
            let samples: Vec<_> = p.drain(..SAMPLES_PER_FRAME * CHANNELS as usize).collect();
            let mut pcm = Vec::with_capacity(PCM_BYTES);
            for s in samples {
                pcm.extend_from_slice(&s.to_le_bytes());
            }
            let _ = tx.try_send(packet(0, &pcm));
        }
    }

    pub struct Playback {
        _stream: cpal::Stream,
        queue: Arc<Mutex<VecDeque<i16>>>,
        gain: Arc<Mutex<(f32, bool)>>,
        alive: Arc<std::sync::atomic::AtomicBool>,
    }
    impl Playback {
        pub fn start(id: &str) -> Result<Self, String> {
            let device = output(id)?;
            let supported = device.default_output_config().map_err(|e| e.to_string())?;
            let config = StreamConfig {
                channels: CHANNELS as u16,
                sample_rate: cpal::SampleRate(RATE),
                buffer_size: cpal::BufferSize::Default,
            };
            let queue = Arc::new(Mutex::new(VecDeque::<i16>::with_capacity(RATE as usize)));
            let gain = Arc::new(Mutex::new((1.0, false)));
            let alive = Arc::new(std::sync::atomic::AtomicBool::new(true));
            let make_error = || {
                let alive = alive.clone();
                move |e| {
                    alive.store(false, std::sync::atomic::Ordering::Relaxed);
                    eprintln!("audio playback error: {e}");
                }
            };
            let stream = match supported.sample_format() {
                SampleFormat::I16 => {
                    let q = queue.clone();
                    let g = gain.clone();
                    device.build_output_stream(
                        &config,
                        move |d: &mut [i16], _| fill_i16(d, &q, &g),
                        make_error(),
                        None,
                    )
                }
                SampleFormat::F32 => {
                    let q = queue.clone();
                    let g = gain.clone();
                    device.build_output_stream(
                        &config,
                        move |d: &mut [f32], _| {
                            let mut temp = vec![0i16; d.len()];
                            fill_i16(&mut temp, &q, &g);
                            for (o, s) in d.iter_mut().zip(temp) {
                                *o = s as f32 / i16::MAX as f32;
                            }
                        },
                        make_error(),
                        None,
                    )
                }
                other => return Err(format!("Unsupported output format: {other:?}")),
            }
            .map_err(|e| e.to_string())?;
            stream.play().map_err(|e| e.to_string())?;
            Ok(Self {
                _stream: stream,
                queue,
                gain,
                alive,
            })
        }
        pub fn write(&mut self, pcm: Vec<u8>) -> bool {
            if !self.alive.load(std::sync::atomic::Ordering::Relaxed) {
                return false;
            }
            let mut q = self.queue.lock().unwrap();
            for b in pcm.chunks_exact(2) {
                q.push_back(i16::from_le_bytes([b[0], b[1]]));
            }
            while q.len() > RATE as usize {
                q.pop_front();
            }
            true
        }
        pub fn gain(&mut self, volume: f32, muted: bool) {
            *self.gain.lock().unwrap() = (volume.clamp(0.0, 1.0), muted);
        }
        pub fn stop(&mut self) {}
    }
    fn fill_i16(out: &mut [i16], q: &Arc<Mutex<VecDeque<i16>>>, gain: &Arc<Mutex<(f32, bool)>>) {
        let mut q = q.lock().unwrap();
        let (v, m) = *gain.lock().unwrap();
        for o in out {
            let s = q.pop_front().unwrap_or(0);
            *o = if m { 0 } else { (s as f32 * v) as i16 };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audio_packets_are_versioned_and_validated() {
        let p = packet(9, &vec![0; PCM_BYTES]);
        assert!(valid_packet(&p));
        assert_eq!(p[0..4], [DATA, PROTOCOL, CHANNELS, 1]);
        assert_eq!(u32::from_le_bytes(p[8..12].try_into().unwrap()), 9);
        let mut bad = p.clone();
        bad[1] += 1;
        assert!(!valid_packet(&bad));
        assert!(!valid_packet(&p[..10]));
    }

    #[test]
    fn frame_size_is_exactly_twenty_milliseconds() {
        assert_eq!(SAMPLES_PER_FRAME, 960);
        assert_eq!(PCM_BYTES, 3840);
    }
}
