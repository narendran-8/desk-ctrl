//! Voice control, agent side: the phone sends its microphone audio, the agent turns it into text
//! (Whistle) and, when asked, into an action (Needle 3), and sends the answer back. Nothing is
//! typed or pressed here: the phone decides what a phrase means and sends ordinary key frames.
//!
//! The models live in a Python helper (`agent/voice/voice_helper.py`, installed by
//! `setup_voice.sh`) that stays loaded between phrases and talks one JSON line per request.
//!
//! Phone -> agent: `0x06 op ...`  (1 begin [mode], 2 audio = 16 kHz mono i16 LE, 3 end, 4 cancel,
//! 5 intent request = UTF-8 text).  Agent -> phone: `0x15 flag chunk`: a JSON text cut in pieces
//! of at most 248 bytes (flag 0 = more follows, 1 = last piece), so it also fits a Bluetooth frame.

use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const FRAME_IN: u8 = 0x06;
pub const FRAME_OUT: u8 = 0x15;

const BEGIN: u8 = 1;
const AUDIO: u8 = 2;
const END: u8 = 3;
const CANCEL: u8 = 4;
const INTENT: u8 = 5;

const RATE: usize = 16_000;
/// At most 30 seconds of speech (what Whistle takes in one pass).
pub const MAX_AUDIO_BYTES: usize = RATE * 2 * 30;
/// Less than this (0.2 s) is a bump on the button, not speech.
const MIN_AUDIO_BYTES: usize = RATE * 2 / 5;
const PIECE: usize = 248;

/// The model has to be loaded (and downloaded the first time) before it answers.
const FIRST_ANSWER: Duration = Duration::from_secs(180);

const NOT_INSTALLED: &str =
    r#"{"t":"unavailable","msg":"Voice engine is not installed on this computer. Run setup_voice.sh there."}"#;

/// The helper script, written next to the Python environment by [`Engine::prepare`].
const HELPER_SCRIPT: &str = include_str!("../voice/voice_helper.py");

/// Fallback when systemd is not available: lowest scheduling class and a cap on virtual memory.
const LAUNCH: &str = r#"ulimit -v 8388608 2>/dev/null; if command -v chrt >/dev/null 2>&1; then exec chrt -i 0 "$@"; else exec nice -n 19 "$@"; fi"#;

/// The helper runs in its own systemd scope with hard limits on memory (no swap) and on the
/// number of threads, and in the "idle" scheduling class, so it only gets CPU the desktop is not
/// using. The Needle engine starts one busy-waiting thread per CPU core of the machine and pins
/// them there: never restrict it to fewer cores (a CPU quota or an affinity mask made a 1 s
/// recognition take minutes), and never give it normal priority (the dev machine froze twice).
fn scope_args() -> Vec<String> {
    [
        "systemd-run", "--user", "--scope", "--quiet", "--collect", "-p", "MemoryMax=1536M", "-p",
        "MemorySwapMax=0", "-p", "TasksMax=128", "-p", "CPUWeight=1", "-p", "IOWeight=1", "--",
    ]
    .map(String::from)
    .to_vec()
}

fn have_program(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).any(|d| d.join(name).is_file()))
        .unwrap_or(false)
}

fn scope_available() -> bool {
    static OK: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *OK.get_or_init(|| {
        Command::new("systemd-run")
            .args(["--user", "--scope", "--quiet", "-p", "MemoryMax=64M", "--", "true"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    })
}

/// The program and arguments that start the helper `argv` with the safety limits.
fn launch_command(argv: &[String], scope: bool, chrt: bool) -> (String, Vec<String>) {
    let low: Vec<String> = if chrt {
        ["chrt", "-i", "0"].map(String::from).to_vec()
    } else {
        ["nice", "-n", "19"].map(String::from).to_vec()
    };
    if scope {
        let mut a = scope_args();
        let program = a.remove(0);
        a.extend(low);
        a.extend_from_slice(argv);
        (program, a)
    } else {
        let mut a = vec!["-c".to_string(), LAUNCH.to_string(), "sh".to_string()];
        a.extend_from_slice(argv);
        ("sh".to_string(), a)
    }
}

struct Helper {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<String>,
}

/// The Python helper process: started on first use, kept loaded, restarted if it dies.
pub struct Engine {
    argv: Option<Vec<String>>,
    helper: Mutex<Option<Helper>>,
}

impl Default for Engine {
    fn default() -> Self {
        Self::system()
    }
}

fn voice_dir() -> Option<std::path::PathBuf> {
    let home = std::env::var_os("HOME")?;
    Some(std::path::Path::new(&home).join(".local/share/deskctrl/voice"))
}

impl Engine {
    /// The helper installed by `setup_voice.sh`, or (tests, other setups) the program named in
    /// `DESK_VOICE_HELPER`. `DESK_NO_VOICE=1` switches voice control off.
    pub fn system() -> Self {
        let argv = if std::env::var_os("DESK_NO_VOICE").is_some() {
            None
        } else if let Some(p) = std::env::var_os("DESK_VOICE_HELPER") {
            Some(vec![p.to_string_lossy().into_owned()])
        } else {
            voice_dir().and_then(|dir| {
                let python = dir.join("env/bin/python");
                python.exists().then(|| {
                    vec![python.to_string_lossy().into_owned(), dir.join("voice_helper.py").to_string_lossy().into_owned()]
                })
            })
        };
        Self { argv, helper: Mutex::new(None) }
    }

    /// An engine that starts exactly this program (and its arguments).
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn with_argv(argv: Vec<String>) -> Self {
        Self { argv: Some(argv), helper: Mutex::new(None) }
    }

    pub fn available(&self) -> bool {
        self.argv.is_some()
    }

    /// Put the helper script where the Python environment expects it (it is part of this program).
    pub fn prepare() {
        let Some(dir) = voice_dir() else { return };
        if !dir.join("env/bin/python").exists() {
            return;
        }
        let script = dir.join("voice_helper.py");
        if std::fs::read_to_string(&script).ok().as_deref() != Some(HELPER_SCRIPT) {
            let _ = std::fs::write(script, HELPER_SCRIPT);
        }
    }

    fn spawn(argv: &[String]) -> std::io::Result<Helper> {
        let (program, args) = launch_command(argv, scope_available(), have_program("chrt"));
        let mut child = Command::new(program)
            .args(args)
            .env("NEEDLE_TELEMETRY", "0")
            .env("DO_NOT_TRACK", "1")
            .env("OMP_NUM_THREADS", "2")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        let stdin = child.stdin.take().expect("piped stdin");
        let stdout = child.stdout.take().expect("piped stdout");
        let (tx, lines) = mpsc::channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines() {
                match line {
                    Ok(l) => {
                        if tx.send(l).is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
        });
        Ok(Helper { child, stdin, lines })
    }

    /// One request line in, one answer line out. Requests are served one at a time; a helper
    /// that does not answer in `wait` is killed (and started afresh next time).
    pub fn request(&self, line: &str, wait: Duration) -> Result<String, String> {
        let argv = self.argv.as_ref().ok_or("voice engine not installed")?;
        let mut slot = self.helper.lock().unwrap();
        if let Some(h) = slot.as_mut() {
            if matches!(h.child.try_wait(), Ok(Some(_))) {
                *slot = None;
            }
        }
        if slot.is_none() {
            *slot = Some(Self::spawn(argv).map_err(|e| format!("could not start the voice helper: {e}"))?);
        }
        let h = slot.as_mut().unwrap();
        let sent = writeln!(h.stdin, "{line}").and_then(|_| h.stdin.flush());
        let answer = match sent {
            Ok(()) => h.lines.recv_timeout(wait).map_err(|e| match e {
                mpsc::RecvTimeoutError::Timeout => "the voice helper took too long".to_string(),
                mpsc::RecvTimeoutError::Disconnected => "the voice helper stopped".to_string(),
            }),
            Err(e) => Err(format!("the voice helper stopped: {e}")),
        };
        if answer.is_err() {
            if let Some(mut h) = slot.take() {
                let _ = h.child.kill();
                let _ = h.child.wait();
            }
        }
        answer
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        if let Some(mut h) = self.helper.lock().unwrap().take() {
            let _ = h.child.kill();
            let _ = h.child.wait();
        }
    }
}

/// `text` as a JSON string (with the quotes).
pub fn json_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// A JSON text as the frames sent to the phone.
pub fn out_frames(json: &str) -> Vec<Vec<u8>> {
    let bytes = json.as_bytes();
    let n = bytes.len().div_ceil(PIECE).max(1);
    (0..n)
        .map(|i| {
            let piece = &bytes[(i * PIECE).min(bytes.len())..((i + 1) * PIECE).min(bytes.len())];
            let mut f = vec![FRAME_OUT, u8::from(i + 1 == n)];
            f.extend_from_slice(piece);
            f
        })
        .collect()
}

/// A 16 kHz mono 16-bit WAV file.
fn wav(pcm: &[u8]) -> Vec<u8> {
    let mut w = Vec::with_capacity(44 + pcm.len());
    w.extend_from_slice(b"RIFF");
    w.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
    w.extend_from_slice(b"WAVEfmt ");
    w.extend_from_slice(&16u32.to_le_bytes());
    w.extend_from_slice(&1u16.to_le_bytes()); // PCM
    w.extend_from_slice(&1u16.to_le_bytes()); // mono
    w.extend_from_slice(&(RATE as u32).to_le_bytes());
    w.extend_from_slice(&(RATE as u32 * 2).to_le_bytes());
    w.extend_from_slice(&2u16.to_le_bytes());
    w.extend_from_slice(&16u16.to_le_bytes());
    w.extend_from_slice(b"data");
    w.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
    w.extend_from_slice(pcm);
    w
}

static TEMP_N: AtomicU64 = AtomicU64::new(0);

fn write_temp_wav(pcm: &[u8]) -> std::io::Result<std::path::PathBuf> {
    let path = std::env::temp_dir().join(format!(
        "deskctrl-voice-{}-{}.wav",
        std::process::id(),
        TEMP_N.fetch_add(1, Ordering::Relaxed)
    ));
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600); // the recording is private
    }
    let mut f = opts.open(&path)?;
    f.write_all(&wav(pcm))?;
    Ok(path)
}

pub type Reply = Arc<dyn Fn(Vec<u8>) + Send + Sync>;

/// What one connected phone is saying right now.
pub struct VoiceSession {
    engine: Arc<Engine>,
    reply: Reply,
    audio: Vec<u8>,
    command: bool,
    listening: bool,
}

impl VoiceSession {
    pub fn new(engine: Arc<Engine>, reply: Reply) -> Self {
        Self { engine, reply, audio: Vec::new(), command: false, listening: false }
    }

    fn send_json(reply: &Reply, json: &str) {
        for f in out_frames(json) {
            reply(f);
        }
    }

    /// Handles a frame if it is a voice frame; false means "not mine".
    pub fn handle(&mut self, data: &[u8]) -> bool {
        if data.first() != Some(&FRAME_IN) {
            return false;
        }
        match data.get(1).copied() {
            Some(BEGIN) => {
                self.audio.clear();
                self.command = data.get(2).copied() == Some(1);
                self.listening = self.engine.available();
                if !self.listening {
                    Self::send_json(&self.reply, NOT_INSTALLED);
                }
            }
            Some(AUDIO) if self.listening => {
                let room = MAX_AUDIO_BYTES.saturating_sub(self.audio.len());
                let chunk = &data[2..];
                self.audio.extend_from_slice(&chunk[..chunk.len().min(room)]);
            }
            Some(END) if self.listening => {
                self.listening = false;
                let pcm = std::mem::take(&mut self.audio);
                if pcm.len() < MIN_AUDIO_BYTES {
                    Self::send_json(&self.reply, r#"{"t":"text","text":""}"#);
                    return true;
                }
                let (engine, reply, command) = (self.engine.clone(), self.reply.clone(), self.command);
                std::thread::spawn(move || {
                    let json = match write_temp_wav(&pcm) {
                        Err(e) => format!(r#"{{"t":"error","msg":{}}}"#, json_string(&format!("temp file: {e}"))),
                        Ok(path) => {
                            let mode = if command { "command" } else { "dictate" };
                            let line = format!(
                                r#"{{"op":"transcribe","mode":"{mode}","wav":{}}}"#,
                                json_string(&path.to_string_lossy())
                            );
                            let answer = engine.request(&line, FIRST_ANSWER);
                            let _ = std::fs::remove_file(&path);
                            answer.unwrap_or_else(|e| format!(r#"{{"t":"error","msg":{}}}"#, json_string(&e)))
                        }
                    };
                    Self::send_json(&reply, &json);
                });
            }
            Some(CANCEL) => {
                self.audio.clear();
                self.listening = false;
            }
            Some(INTENT) => {
                let text = String::from_utf8_lossy(&data[2..]).into_owned();
                if !self.engine.available() {
                    Self::send_json(&self.reply, NOT_INSTALLED);
                    return true;
                }
                let (engine, reply) = (self.engine.clone(), self.reply.clone());
                std::thread::spawn(move || {
                    let line = format!(r#"{{"op":"intent","text":{}}}"#, json_string(&text));
                    let json = engine
                        .request(&line, FIRST_ANSWER)
                        .unwrap_or_else(|e| format!(r#"{{"t":"error","msg":{}}}"#, json_string(&e)));
                    Self::send_json(&reply, &json);
                });
            }
            _ => {}
        }
        true
    }
}

/// An engine whose helper is a shell script answering like the real one (for tests in other modules).
#[cfg(all(test, unix))]
pub fn fake_engine() -> Arc<Engine> {
    let dir = std::env::temp_dir().join(format!("deskctrl-fake-helper-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("fake_helper.sh");
    std::fs::write(
        &path,
        r#"#!/bin/sh
while read line; do
  case "$line" in
    *'"op":"transcribe"'*'"mode":"command"'*) echo '{"t":"text","text":"close this window","ms":1}' ;;
    *'"op":"transcribe"'*) echo '{"t":"text","text":"hello world","ms":1}' ;;
    *'"op":"intent"'*) echo '{"t":"intent","calls":[{"name":"close_app","arguments":{}}],"confidence":0.5,"ms":1}' ;;
    *) echo '{"t":"error","msg":"?"}' ;;
  esac
done
"#,
    )
    .unwrap();
    Arc::new(Engine::with_argv(vec!["sh".to_string(), path.to_string_lossy().into_owned()]))
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::sync::mpsc::channel;

    /// A helper that answers like the real one, without any model.
    fn fake_helper(dir: &std::path::Path) -> Vec<String> {
        let path = dir.join("fake_helper.sh");
        std::fs::write(
            &path,
            r#"#!/bin/sh
while read line; do
  case "$line" in
    *'"op":"transcribe"'*'"mode":"command"'*) echo '{"t":"text","text":"close this window","ms":1}' ;;
    *'"op":"transcribe"'*) echo '{"t":"text","text":"hello world","ms":1}' ;;
    *'"op":"intent"'*) echo '{"t":"intent","calls":[{"name":"close_app","arguments":{}}],"confidence":0.5,"ms":1}' ;;
    *) echo '{"t":"error","msg":"?"}' ;;
  esac
done
"#,
        )
        .unwrap();
        vec!["sh".to_string(), path.to_string_lossy().into_owned()]
    }

    fn session(argv: Option<Vec<String>>) -> (VoiceSession, Receiver<Vec<u8>>) {
        let (tx, rx) = channel();
        let tx = Mutex::new(tx);
        let engine = Arc::new(match argv {
            Some(a) => Engine::with_argv(a),
            None => Engine { argv: None, helper: Mutex::new(None) },
        });
        (VoiceSession::new(engine, Arc::new(move |f| drop(tx.lock().unwrap().send(f)))), rx)
    }

    /// The JSON the phone would put together from the frames.
    fn answer(rx: &Receiver<Vec<u8>>) -> String {
        let mut text = Vec::new();
        loop {
            let f = rx.recv_timeout(Duration::from_secs(10)).expect("an answer");
            assert_eq!(f[0], FRAME_OUT);
            text.extend_from_slice(&f[2..]);
            if f[1] == 1 {
                return String::from_utf8(text).unwrap();
            }
        }
    }

    fn speech(seconds: f32) -> Vec<u8> {
        vec![1u8; (RATE as f32 * 2.0 * seconds) as usize]
    }

    fn feed(s: &mut VoiceSession, mode: u8, pcm: &[u8]) {
        assert!(s.handle(&[FRAME_IN, BEGIN, mode]));
        for c in pcm.chunks(250) {
            let mut f = vec![FRAME_IN, AUDIO];
            f.extend_from_slice(c);
            assert!(s.handle(&f));
        }
        assert!(s.handle(&[FRAME_IN, END]));
    }

    fn temp_dir(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("deskctrl-test-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn other_frames_are_not_voice() {
        let (mut s, _rx) = session(None);
        assert!(!s.handle(&[0x01, 0, 4]));
        assert!(!s.handle(&[0x00]));
        assert!(!s.handle(&[]));
    }

    #[test]
    fn speech_becomes_text_in_dictate_and_command_mode() {
        let dir = temp_dir("speech");
        let (mut s, rx) = session(Some(fake_helper(&dir)));
        feed(&mut s, 0, &speech(1.5));
        assert_eq!(answer(&rx), r#"{"t":"text","text":"hello world","ms":1}"#);
        feed(&mut s, 1, &speech(1.0));
        assert!(answer(&rx).contains("close this window"), "command mode is told to the helper");
    }

    #[test]
    fn a_bump_on_the_button_is_empty_text_without_the_helper() {
        let (mut s, rx) = session(Some(vec!["false".into()]));
        feed(&mut s, 0, &speech(0.05));
        assert_eq!(answer(&rx), r#"{"t":"text","text":""}"#);
    }

    #[test]
    fn an_action_is_asked_for_with_the_text_as_given() {
        let dir = temp_dir("intent");
        let (mut s, rx) = session(Some(fake_helper(&dir)));
        let mut f = vec![FRAME_IN, INTENT];
        f.extend_from_slice("close \"this\" window".as_bytes());
        assert!(s.handle(&f));
        let a = answer(&rx);
        assert!(a.contains(r#""name":"close_app""#), "{a}");
    }

    #[test]
    fn without_the_engine_the_phone_is_told_so() {
        let (mut s, rx) = session(None);
        s.handle(&[FRAME_IN, BEGIN, 0]);
        assert!(answer(&rx).contains("unavailable"));
        s.handle(&[FRAME_IN, AUDIO, 1, 2, 3]); // ignored
        s.handle(&[FRAME_IN, END]);
        assert!(rx.recv_timeout(Duration::from_millis(200)).is_err(), "nothing more");
    }

    #[test]
    fn a_helper_that_dies_gives_an_error_and_the_next_phrase_starts_a_new_one() {
        let (mut s, rx) = session(Some(vec!["false".into()]));
        feed(&mut s, 0, &speech(1.0));
        assert!(answer(&rx).contains(r#""t":"error""#));
    }

    #[test]
    fn audio_is_capped_at_thirty_seconds() {
        let (mut s, _rx) = session(Some(vec!["false".into()]));
        s.handle(&[FRAME_IN, BEGIN, 0]);
        for _ in 0..(MAX_AUDIO_BYTES / 250 + 100) {
            let mut f = vec![FRAME_IN, AUDIO];
            f.extend_from_slice(&[0u8; 250]);
            s.handle(&f);
        }
        assert_eq!(s.audio.len(), MAX_AUDIO_BYTES);
    }

    #[test]
    fn long_json_is_cut_in_pieces_that_fit_a_bluetooth_frame() {
        let json = format!(r#"{{"t":"text","text":"{}"}}"#, "x".repeat(700));
        let frames = out_frames(&json);
        assert_eq!(frames.len(), 3);
        assert!(frames.iter().all(|f| f.len() <= 250 && f[0] == FRAME_OUT));
        assert_eq!(frames.iter().map(|f| f[1]).collect::<Vec<_>>(), [0, 0, 1]);
        let joined: Vec<u8> = frames.iter().flat_map(|f| f[2..].to_vec()).collect();
        assert_eq!(String::from_utf8(joined).unwrap(), json);
    }

    #[test]
    fn json_strings_are_escaped() {
        assert_eq!(json_string("a\"b\\c\nd"), r#""a\"b\\c\nd""#);
        assert_eq!(json_string("é"), "\"é\"");
    }

    #[test]
    fn the_wav_has_a_proper_header() {
        let w = wav(&[0, 0, 1, 0]);
        assert_eq!(&w[..4], b"RIFF");
        assert_eq!(u32::from_le_bytes(w[4..8].try_into().unwrap()), 40);
        assert_eq!(u32::from_le_bytes(w[24..28].try_into().unwrap()), 16000);
        assert_eq!(&w[36..40], b"data");
        assert_eq!(w.len(), 48);
    }

    #[test]
    fn the_helper_is_started_with_limits_but_never_with_fewer_cores() {
        let argv = vec!["python".to_string(), "helper.py".to_string()];
        let (program, args) = launch_command(&argv, true, true);
        assert_eq!(program, "systemd-run");
        for needed in ["MemoryMax=1536M", "MemorySwapMax=0", "TasksMax=128", "CPUWeight=1", "--scope"] {
            assert!(args.iter().any(|a| a == needed), "{needed} in {args:?}");
        }
        assert!(
            !args.iter().any(|a| a.starts_with("CPUQuota") || a.contains("taskset")),
            "a CPU quota or core mask starves the engine's one-thread-per-core pool: {args:?}"
        );
        assert!(args.ends_with(&["chrt".into(), "-i".into(), "0".into(), "python".into(), "helper.py".into()]));
        let (_, args) = launch_command(&argv, true, false);
        assert!(args.ends_with(&["nice".into(), "-n".into(), "19".into(), "python".into(), "helper.py".into()]));
        let (program, args) = launch_command(&argv, false, true);
        assert_eq!(program, "sh");
        assert!(args[1].contains("ulimit -v") && args[1].contains("chrt -i 0"), "{args:?}");
        assert!(args.ends_with(&argv));
    }

    #[test]
    fn the_helper_removes_a_cut_off_model_download_so_it_is_fetched_again() {
        // A download cut short leaves an empty .cact that the Python package trusts forever.
        let home = temp_dir("heal");
        let cache = home.join(".cache/cactus-needle/v3/1.0");
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::write(cache.join("needle3.cact"), b"").unwrap();
        std::fs::write(cache.join("whistle.cact"), vec![1u8; 2_000_000]).unwrap();
        let script = std::env::temp_dir().join(format!("deskctrl-helper-{}.py", std::process::id()));
        std::fs::write(&script, HELPER_SCRIPT).unwrap();
        let out = Command::new("python3")
            .arg("-c")
            .arg(format!(
                "import importlib.util as u; s=u.spec_from_file_location('h', {:?}); m=u.module_from_spec(s); s.loader.exec_module(m); m.heal_cache()",
                script.to_string_lossy()
            ))
            .env("HOME", &home)
            .output();
        let Ok(out) = out else { return }; // no python3 here
        assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
        assert!(!cache.join("needle3.cact").exists(), "the empty file is gone");
        assert!(cache.join("whistle.cact").exists(), "a complete file stays");
    }
}
