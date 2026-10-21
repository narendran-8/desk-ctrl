//! Volume and screen brightness, read from the computer so the phone can show the real
//! percentage while the edge strips are used.
//!
//! Wire format, agent -> phone: `[0x12, volume, brightness, muted]`. Volume and brightness are
//! percentages, or [`UNKNOWN`] when they cannot be read on this computer. `muted` is 0 or 1.

#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::Path;
#[cfg(unix)]
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tokio::sync::watch;

pub const FRAME_ID: u8 = 0x12;
pub const UNKNOWN: u8 = 0xFF;

/// `[volume, brightness, muted]`
pub type Levels = [u8; 3];
/// Not read yet (never sent). A computer that cannot report anything sends `[UNKNOWN, UNKNOWN, 0]`,
/// which tells the phone it can show "not supported" messages.
pub const NOTHING: Levels = [0xFE, 0xFE, 0];

/// `wpctl get-volume` prints `Volume: 0.45` (plus ` [MUTED]` when muted).
#[cfg_attr(windows, allow(dead_code))]
pub fn parse_wpctl(out: &str) -> Option<(u8, bool)> {
    let v: f32 = out.split_whitespace().nth(1)?.parse().ok()?;
    Some(((v * 100.0).round().clamp(0.0, 250.0) as u8, out.contains("MUTED")))
}

/// `pactl get-sink-volume` prints `Volume: front-left: 29491 /  45% / ...`.
#[cfg_attr(windows, allow(dead_code))]
pub fn parse_pactl(out: &str) -> Option<u8> {
    let pct = out.split('%').next()?;
    let digits: String = pct.chars().rev().take_while(|c| c.is_ascii_digit()).collect::<Vec<_>>().into_iter().rev().collect();
    digits.parse().ok()
}

/// Brightness percentage of the first backlight under `dir`.
#[cfg_attr(windows, allow(dead_code))]
pub fn read_brightness(dir: &Path) -> Option<u8> {
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let num = |f: &str| {
            std::fs::read_to_string(entry.path().join(f)).ok()?.trim().parse::<f64>().ok()
        };
        if let (Some(now), Some(max)) = (num("brightness"), num("max_brightness")) {
            if max > 0.0 {
                return Some((now / max * 100.0).round().clamp(0.0, 100.0) as u8);
            }
        }
    }
    None
}

/// Run a command as the logged-in user: the agent may have been started with `sudo`, and the
/// sound server only answers its own user.
#[cfg(unix)]
fn run(program: &str, args: &[&str]) -> Option<String> {
    let mut cmd = Command::new(program);
    cmd.args(args).stderr(std::process::Stdio::null());
    // SAFETY: geteuid has no preconditions.
    if unsafe { libc::geteuid() } == 0 {
        if let Some(uid) = std::env::var("SUDO_UID").ok().and_then(|u| u.parse::<u32>().ok()) {
            cmd.uid(uid).env("XDG_RUNTIME_DIR", format!("/run/user/{uid}"));
        }
    }
    let out = cmd.output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).to_string())
}

#[cfg(unix)]
fn read_volume() -> Option<(u8, bool)> {
    if let Some(v) = run("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"]).as_deref().and_then(parse_wpctl) {
        return Some(v);
    }
    let vol = run("pactl", &["get-sink-volume", "@DEFAULT_SINK@"]).as_deref().and_then(parse_pactl)?;
    let muted = run("pactl", &["get-sink-mute", "@DEFAULT_SINK@"]).is_some_and(|m| m.contains("yes"));
    Some((vol, muted))
}

#[cfg(unix)]
pub fn read() -> Levels {
    let (volume, muted) = read_volume().unwrap_or((UNKNOWN, false));
    let brightness = read_brightness(Path::new("/sys/class/backlight")).unwrap_or(UNKNOWN);
    [volume, brightness, muted as u8]
}

/// Windows: the volume and brightness are not read yet (the phone says "not supported" for the
/// percentage; the volume and mute keys themselves work).
#[cfg(windows)]
pub fn read() -> Levels {
    [UNKNOWN, UNKNOWN, 0]
}

/// Polls the levels; tells every phone when they change and repeats them every few seconds
/// so a phone that just connected over Bluetooth catches up.
pub fn spawn(
    stop: Arc<AtomicBool>,
    wifi: watch::Sender<Levels>,
    bluetooth: impl Fn(&[u8]) + Send + 'static,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let mut previous = NOTHING;
        let mut last_sent = Instant::now() - Duration::from_secs(10);
        while !stop.load(Ordering::Relaxed) {
            let now = read();
            if now != previous || last_sent.elapsed() >= Duration::from_secs(3) {
                previous = now;
                last_sent = Instant::now();
                let _ = wifi.send(now);
                bluetooth(&[FRAME_ID, now[0], now[1], now[2]]);
            }
            thread::sleep(Duration::from_millis(400));
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn parses_wpctl_output() {
        assert_eq!(parse_wpctl("Volume: 0.45\n"), Some((45, false)));
        assert_eq!(parse_wpctl("Volume: 1.00 [MUTED]\n"), Some((100, true)));
        assert_eq!(parse_wpctl("Volume: 0.07\n"), Some((7, false)));
        assert_eq!(parse_wpctl("nonsense"), None);
    }

    #[test]
    fn parses_pactl_output() {
        let out = "Volume: front-left: 29491 /  45% / -20.99 dB,   front-right: 29491 /  45% / -20.99 dB\n";
        assert_eq!(parse_pactl(out), Some(45));
        assert_eq!(parse_pactl("Volume: mono: 65536 / 100% / 0.00 dB"), Some(100));
        assert_eq!(parse_pactl("no percent here"), None);
    }

    #[test]
    fn brightness_is_a_percentage_of_the_maximum() {
        let root = std::env::temp_dir().join(format!("deskctrl-bl-{}", std::process::id()));
        let d = root.join("intel_backlight");
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("brightness"), "480\n").unwrap();
        fs::write(d.join("max_brightness"), "960\n").unwrap();
        assert_eq!(read_brightness(&root), Some(50));
        fs::remove_dir_all(&root).unwrap();
        assert_eq!(read_brightness(Path::new("/nonexistent-dir")), None);
    }
}
