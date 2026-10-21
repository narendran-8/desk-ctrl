//! Keyboard lock lights (Caps / Num / Scroll Lock), read from the kernel's LED
//! files so the phone can show the real state - also when the key was pressed
//! on the computer's own keyboard.
//!
//! Wire format, agent -> phone: `[0x10, flags]`, flags bit0 Caps, bit1 Num, bit2 Scroll.

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tokio::sync::watch;

pub const FRAME_ID: u8 = 0x10;
/// Sent to every phone once a second so it can tell a live link from a dead one.
pub const HEARTBEAT: u8 = 0x11;
/// Value of the watch channel while no LED could be read.
pub const UNKNOWN: u8 = 0xFF;

const CAPS: u8 = 1;
const NUM: u8 = 2;
const SCROLL: u8 = 4;

/// Flags for every lock light found under `dir`, or None if there are none.
#[cfg_attr(windows, allow(dead_code))]
pub fn read(dir: &Path) -> Option<u8> {
    let mut found = false;
    let mut flags = 0u8;
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let bit = if name.contains("capslock") {
            CAPS
        } else if name.contains("numlock") {
            NUM
        } else if name.contains("scrolllock") {
            SCROLL
        } else {
            continue;
        };
        found = true;
        let on = std::fs::read_to_string(entry.path().join("brightness"))
            .ok()
            .and_then(|v| v.trim().parse::<u32>().ok())
            .map_or(false, |v| v > 0);
        if on {
            flags |= bit;
        }
    }
    found.then_some(flags)
}

/// The lock lights of this computer now.
#[cfg(unix)]
fn current() -> Option<u8> {
    read(Path::new("/sys/class/leds"))
}

/// The lock lights of this computer now (the "toggled" bit of each lock key).
#[cfg(windows)]
fn current() -> Option<u8> {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{GetKeyState, VK_CAPITAL, VK_NUMLOCK, VK_SCROLL};
    let on = |vk: u16| (unsafe { GetKeyState(vk as i32) } & 1) != 0;
    Some(if on(VK_CAPITAL) { CAPS } else { 0 } | if on(VK_NUMLOCK) { NUM } else { 0 } | if on(VK_SCROLL) { SCROLL } else { 0 })
}

/// Polls the lights and tells every phone when they change. The state is also
/// re-sent every second, so a phone that just connected (or missed a frame) catches up.
pub fn spawn(
    stop: Arc<AtomicBool>,
    wifi: watch::Sender<u8>,
    bluetooth: impl Fn(&[u8]) + Send + 'static,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let mut previous = None;
        let mut last_sent = Instant::now() - Duration::from_secs(5);
        let mut last_beat = Instant::now() - Duration::from_secs(5);
        while !stop.load(Ordering::Relaxed) {
            // Also on computers without lock lights: the phone needs it to notice a dead link.
            if last_beat.elapsed() >= Duration::from_secs(1) {
                last_beat = Instant::now();
                bluetooth(&[HEARTBEAT]);
            }
            if let Some(flags) = current() {
                if previous != Some(flags) || last_sent.elapsed() >= Duration::from_secs(1) {
                    previous = Some(flags);
                    last_sent = Instant::now();
                    let _ = wifi.send(flags); // Err just means nobody is listening
                    bluetooth(&[FRAME_ID, flags]);
                }
            }
            thread::sleep(Duration::from_millis(100));
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn led(root: &Path, name: &str, value: &str) {
        let d = root.join(name);
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("brightness"), value).unwrap();
    }

    #[test]
    fn reads_lock_lights() {
        let root = std::env::temp_dir().join(format!("deskctrl-leds-{}", std::process::id()));
        led(&root, "input3::capslock", "1\n");
        led(&root, "input3::numlock", "0\n");
        led(&root, "input3::scrolllock", "0\n");
        led(&root, "asus::kbd_backlight", "3\n"); // not a lock light: ignored
        assert_eq!(read(&root), Some(CAPS));

        led(&root, "input3::numlock", "1\n");
        assert_eq!(read(&root), Some(CAPS | NUM));

        led(&root, "input3::capslock", "0\n");
        led(&root, "input3::numlock", "0\n");
        assert_eq!(read(&root), Some(0));
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn no_lock_lights_means_unknown() {
        let root = std::env::temp_dir().join(format!("deskctrl-noleds-{}", std::process::id()));
        led(&root, "asus::kbd_backlight", "3\n");
        assert_eq!(read(&root), None);
        assert_eq!(read(Path::new("/nonexistent-dir")), None);
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn heartbeat_is_sent_every_second_even_without_lock_lights() {
        use std::sync::Mutex;
        let frames = Arc::new(Mutex::new(Vec::<Vec<u8>>::new()));
        let stop = Arc::new(AtomicBool::new(false));
        let (tx, _rx) = watch::channel(UNKNOWN);
        let sink = frames.clone();
        let t = spawn(stop.clone(), tx, move |p: &[u8]| sink.lock().unwrap().push(p.to_vec()));
        thread::sleep(Duration::from_millis(2300));
        stop.store(true, Ordering::Relaxed);
        t.join().unwrap();
        let beats = frames.lock().unwrap().iter().filter(|f| f.as_slice() == [HEARTBEAT]).count();
        assert!(beats >= 2, "expected a heartbeat about every second, got {beats}");
    }
}
