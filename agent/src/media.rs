//! Now-playing feedback, independent of audio streaming and input injection.
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;

pub const FRAME: u8 = 0x16;
pub const SEEK: u8 = 0x07;
pub type SeekRequest = (u64, u64);

/// Bounded commands are handled by the media worker, never by the input thread.
pub fn handle(frame: &[u8], shared: &crate::server::SharedState) -> bool {
    if frame.first() != Some(&SEEK) {
        return false;
    }
    if frame.len() == 17 {
        let request = (
            u64::from_be_bytes(frame[1..9].try_into().unwrap()),
            u64::from_be_bytes(frame[9..17].try_into().unwrap()),
        );
        if let Some(tx) = &shared.lock().unwrap().media_requests {
            let _ = tx.try_send(request);
        }
    }
    true
}

#[cfg(unix)]
fn track_key(player: &str, track: &str, title: &str, length: i64) -> u64 {
    let value = format!("{player}\0{track}\0{title}\0{length}");
    value.bytes().fold(0xcbf29ce484222325, |h, b| {
        (h ^ b as u64).wrapping_mul(0x100000001b3)
    })
}

pub fn frames(value: &serde_json::Value) -> Vec<Vec<u8>> {
    let bytes = value.to_string().into_bytes();
    bytes
        .chunks(240)
        .enumerate()
        .map(|(i, chunk)| {
            let flags = u8::from(i == 0) | if (i + 1) * 240 >= bytes.len() { 2 } else { 0 };
            let mut out = vec![FRAME, flags];
            out.extend_from_slice(chunk);
            out
        })
        .collect()
}

pub fn spawn(
    stop: Arc<AtomicBool>,
    send: impl Fn(&[u8]) + Send + 'static,
    requests: std::sync::mpsc::Receiver<SeekRequest>,
) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        #[cfg(unix)]
        let bus = zbus::blocking::connection::Builder::session()
            .ok()
            .and_then(|b| b.method_timeout(Duration::from_millis(250)).build().ok());
        let mut previous = serde_json::Value::Null;
        let mut ticks = 0;
        while !stop.load(Ordering::Relaxed) {
            while let Ok((key, position)) = requests.try_recv() {
                #[cfg(unix)]
                if let Some(bus) = &bus {
                    let _ = set_position(bus, key, position);
                }
                #[cfg(windows)]
                let _ = (key, position);
            }
            #[cfg(unix)]
            let info = bus
                .as_ref()
                .and_then(now_playing)
                .unwrap_or_else(|| serde_json::json!({}));
            #[cfg(windows)]
            let info = serde_json::json!({});
            // Repeat periodically so a newly connected phone receives the current song.
            if info != previous || ticks % 4 == 0 {
                for frame in frames(&info) {
                    send(&frame);
                }
                previous = info;
            }
            ticks += 1;
            for _ in 0..10 {
                if stop.load(Ordering::Relaxed) {
                    return;
                }
                match requests.recv_timeout(Duration::from_millis(100)) {
                    Ok((key, position)) => {
                        #[cfg(unix)]
                        if let Some(bus) = &bus {
                            let _ = set_position(bus, key, position);
                        }
                        #[cfg(windows)]
                        let _ = (key, position);
                        break; // report the new position immediately after a seek
                    }
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return,
                    Err(_) => {}
                }
            }
        }
    })
}

#[cfg(unix)]
fn now_playing(bus: &zbus::blocking::Connection) -> Option<serde_json::Value> {
    use std::collections::HashMap;
    use zbus::blocking::Proxy;
    use zbus::zvariant::OwnedValue;
    let dbus = Proxy::new(
        bus,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    )
    .ok()?;
    let mut names: Vec<String> = dbus.call("ListNames", &()).ok()?;
    names.sort();
    let mut paused = None;
    for name in names
        .iter()
        .filter(|n| n.starts_with("org.mpris.MediaPlayer2."))
    {
        let Ok(player) = Proxy::new(
            bus,
            name.as_str(),
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
        ) else {
            continue;
        };
        let status: String = player.get_property("PlaybackStatus").unwrap_or_default();
        if status != "Playing" && status != "Paused" {
            continue;
        }
        let metadata: HashMap<String, OwnedValue> =
            player.get_property("Metadata").unwrap_or_default();
        let title = metadata
            .get("xesam:title")
            .and_then(|v| <&str>::try_from(v).ok())
            .unwrap_or("");
        if title.is_empty() {
            continue;
        }
        let root = Proxy::new(
            bus,
            name.as_str(),
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2",
        )
        .ok()?;
        let app: String = root.get_property("Identity").unwrap_or_default();
        let desktop: String = root.get_property("DesktopEntry").unwrap_or_else(|_| {
            name.trim_start_matches("org.mpris.MediaPlayer2.")
                .split('.')
                .next()
                .unwrap_or("")
                .into()
        });
        let length = metadata
            .get("mpris:length")
            .and_then(|v| i64::try_from(v).ok())
            .unwrap_or(0)
            .max(0);
        let track = metadata
            .get("mpris:trackid")
            .and_then(|v| <&zbus::zvariant::ObjectPath>::try_from(v).ok())
            .map(|p| p.as_str())
            .unwrap_or("");
        let position = player
            .get_property::<i64>("Position")
            .ok()
            .filter(|p| *p >= 0);
        let can_seek = player.get_property::<bool>("CanSeek").unwrap_or(false)
            && !track.is_empty()
            && position.is_some();
        let rate = player.get_property::<f64>("Rate").unwrap_or(1.0);
        let value = serde_json::json!({
            "title":title.chars().take(512).collect::<String>(), "app":app, "playing":status == "Playing", "icon": app_icon(&desktop),
            "positionMs":position.map(|p| p / 1000), "durationMs":length / 1000,
            "rate": if rate.is_finite() { rate } else { 1.0 }, "canSeek":can_seek,
            "seekKey":format!("{:016x}", track_key(name, track, title, length)),
            "player":name, "trackId":track
        });
        if status == "Playing" {
            return Some(value);
        }
        if paused.is_none() {
            paused = Some(value);
        }
    }
    paused
}

#[cfg(unix)]
fn set_position(
    bus: &zbus::blocking::Connection,
    key: u64,
    position_us: u64,
) -> zbus::Result<bool> {
    // Re-read the active session. A stale drag must never seek the next track or another app.
    let Some(info) = now_playing(bus) else {
        return Ok(false);
    };
    if info["seekKey"].as_str() != Some(&format!("{key:016x}")) || info["canSeek"] != true {
        return Ok(false);
    }
    let player = info["player"].as_str().unwrap_or("");
    let track = zbus::zvariant::ObjectPath::try_from(info["trackId"].as_str().unwrap_or("/"))?;
    let length_us = info["durationMs"]
        .as_u64()
        .unwrap_or(0)
        .saturating_mul(1000);
    let position = if length_us > 0 {
        position_us.min(length_us.saturating_sub(1))
    } else {
        position_us
    }
    .min(i64::MAX as u64) as i64;
    let proxy = zbus::blocking::Proxy::new(
        bus,
        player,
        "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Player",
    )?;
    proxy.call::<_, _, ()>("SetPosition", &(track, position))?;
    Ok(true)
}

#[cfg(unix)]
fn app_icon(desktop: &str) -> String {
    use base64::Engine;
    // Resolve only an installed application icon, never arbitrary media artwork URLs.
    if desktop.is_empty() || desktop.contains(['/', '\\']) || desktop.contains("..") {
        return String::new();
    }
    let mut icon = desktop.to_string();
    let home = std::env::var("HOME").unwrap_or_default();
    let roots = [
        format!("{home}/.local/share"),
        "/usr/share".into(),
        "/var/lib/flatpak/exports/share".into(),
        "/var/lib/snapd/desktop".into(),
    ];
    for root in &roots {
        if let Ok(text) = std::fs::read_to_string(format!("{root}/applications/{desktop}.desktop"))
        {
            if let Some(value) = text.lines().find_map(|l| l.strip_prefix("Icon=")) {
                icon = value.into();
                break;
            }
        }
    }
    let mut paths = Vec::new();
    if icon.starts_with('/') {
        paths.push(std::path::PathBuf::from(&icon));
    } else if !icon.contains(['/', '\\']) && !icon.contains("..") {
        for root in &roots {
            let themes = std::fs::read_dir(format!("{root}/icons"))
                .into_iter()
                .flatten()
                .flatten();
            for theme in themes {
                for size in [
                    "32x32", "48x48", "64x64", "128x128", "256x256", "32", "48", "64",
                ] {
                    paths.push(
                        theme
                            .path()
                            .join(size)
                            .join("apps")
                            .join(format!("{icon}.png")),
                    );
                }
            }
            paths.push(std::path::PathBuf::from(format!(
                "{root}/pixmaps/{icon}.png"
            )));
        }
    }
    for path in paths {
        if std::fs::metadata(&path).is_ok_and(|m| m.len() < 1_000_000) {
            if let Ok(reader) = image::ImageReader::open(path) {
                if let Ok(img) = reader.decode() {
                    let mut png = std::io::Cursor::new(Vec::new());
                    if img
                        .thumbnail(24, 24)
                        .write_to(&mut png, image::ImageFormat::Png)
                        .is_ok()
                    {
                        return base64::engine::general_purpose::STANDARD.encode(png.into_inner());
                    }
                }
            }
        }
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unicode_and_icon_feedback_roundtrip_in_bluetooth_sized_frames() {
        let info = serde_json::json!({"title":"தமிழ் 🎵".repeat(100),"app":"Firefox","icon":"abc"});
        let parts = frames(&info);
        assert!(parts.iter().all(|f| f.len() <= 242));
        assert_eq!(parts[0][1] & 1, 1);
        assert_eq!(parts.last().unwrap()[1] & 2, 2);
        let bytes: Vec<u8> = parts.iter().flat_map(|f| f[2..].iter().copied()).collect();
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&bytes).unwrap(),
            info
        );
    }
    #[test]
    fn seek_frame_is_bounded_and_separate_from_input() {
        let shared = Arc::new(std::sync::Mutex::new(crate::server::Shared::default()));
        let (tx, rx) = std::sync::mpsc::sync_channel(1);
        shared.lock().unwrap().media_requests = Some(tx);
        let mut frame = vec![SEEK];
        frame.extend_from_slice(&123u64.to_be_bytes());
        frame.extend_from_slice(&65_000_000u64.to_be_bytes());
        assert!(handle(&frame, &shared));
        assert_eq!(rx.try_recv().unwrap(), (123, 65_000_000));
        assert!(handle(&[SEEK, 1], &shared));
        assert!(rx.try_recv().is_err());
        assert!(!handle(&[1, 0, 4], &shared));
    }
    #[cfg(unix)]
    struct MockPlayer {
        position: Arc<std::sync::atomic::AtomicI64>,
        length: Arc<std::sync::atomic::AtomicI64>,
        changed: Arc<AtomicBool>,
        seekable: Arc<AtomicBool>,
    }
    #[cfg(unix)]
    #[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
    impl MockPlayer {
        #[zbus(property)]
        fn playback_status(&self) -> &str {
            "Playing"
        }
        #[zbus(property)]
        fn metadata(&self) -> std::collections::HashMap<String, zbus::zvariant::OwnedValue> {
            use zbus::zvariant::{ObjectPath, Value};
            let title = if self.changed.load(Ordering::Relaxed) {
                "Next track"
            } else {
                "A Firefox video 🎵"
            };
            let track = if self.changed.load(Ordering::Relaxed) {
                "/vil/test/track2"
            } else {
                "/vil/test/track1"
            };
            std::collections::HashMap::from([
                (
                    "xesam:title".into(),
                    Value::from(title).try_to_owned().unwrap(),
                ),
                (
                    "mpris:length".into(),
                    Value::from(self.length.load(Ordering::Relaxed))
                        .try_to_owned()
                        .unwrap(),
                ),
                (
                    "mpris:trackid".into(),
                    Value::from(ObjectPath::try_from(track).unwrap())
                        .try_to_owned()
                        .unwrap(),
                ),
            ])
        }
        #[zbus(property)]
        fn position(&self) -> i64 {
            self.position.load(Ordering::Relaxed)
        }
        #[zbus(property)]
        fn rate(&self) -> f64 {
            1.0
        }
        #[zbus(property)]
        fn can_seek(&self) -> bool {
            self.seekable.load(Ordering::Relaxed)
        }
        fn set_position(&self, _track: zbus::zvariant::ObjectPath<'_>, position: i64) {
            self.position.store(position, Ordering::Relaxed);
        }
    }
    #[cfg(unix)]
    struct MockApp;
    #[cfg(unix)]
    #[zbus::interface(name = "org.mpris.MediaPlayer2")]
    impl MockApp {
        #[zbus(property)]
        fn identity(&self) -> &str {
            "Firefox"
        }
        #[zbus(property)]
        fn desktop_entry(&self) -> &str {
            "firefox"
        }
    }
    #[cfg(unix)]
    #[test]
    fn reads_title_and_identity_from_a_real_private_mpris_bus() {
        use std::io::BufRead;
        struct PrivateBus(std::process::Child);
        impl Drop for PrivateBus {
            fn drop(&mut self) {
                let _ = self.0.kill();
                let _ = self.0.wait();
            }
        }
        let mut daemon = PrivateBus(
            std::process::Command::new("dbus-daemon")
                .args(["--session", "--nofork", "--print-address=1"])
                .stdout(std::process::Stdio::piped())
                .spawn()
                .unwrap(),
        );
        let mut address = String::new();
        std::io::BufReader::new(daemon.0.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();
        let position = Arc::new(std::sync::atomic::AtomicI64::new(20_000_000));
        let length = Arc::new(std::sync::atomic::AtomicI64::new(120_000_000));
        let changed = Arc::new(AtomicBool::new(false));
        let seekable = Arc::new(AtomicBool::new(true));
        let service = zbus::blocking::connection::Builder::address(address.trim())
            .unwrap()
            .name("org.mpris.MediaPlayer2.viltest")
            .unwrap()
            .serve_at(
                "/org/mpris/MediaPlayer2",
                MockPlayer {
                    position: position.clone(),
                    length: length.clone(),
                    changed: changed.clone(),
                    seekable: seekable.clone(),
                },
            )
            .unwrap()
            .serve_at("/org/mpris/MediaPlayer2", MockApp)
            .unwrap()
            .build()
            .unwrap();
        let client = zbus::blocking::connection::Builder::address(address.trim())
            .unwrap()
            .build()
            .unwrap();
        let info = now_playing(&client).unwrap();
        assert_eq!(info["title"], "A Firefox video 🎵");
        assert_eq!(info["app"], "Firefox");
        assert_eq!(info["playing"], true);
        // When Firefox has a PNG icon installed, verify the transmitted icon
        // really decodes as a small image, rather than album art or an app id.
        let encoded = info["icon"].as_str().unwrap();
        if !encoded.is_empty() {
            use base64::Engine;
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(encoded)
                .unwrap();
            let icon = image::load_from_memory(&bytes).unwrap();
            assert!(icon.width() <= 24 && icon.height() <= 24);
        }
        assert_eq!(info["positionMs"], 20000);
        assert_eq!(info["durationMs"], 120000);
        assert_eq!(info["canSeek"], true);
        let key = u64::from_str_radix(info["seekKey"].as_str().unwrap(), 16).unwrap();
        assert!(set_position(&client, key, 90_000_000).unwrap());
        assert_eq!(position.load(Ordering::Relaxed), 90_000_000);
        assert!(!set_position(&client, key.wrapping_add(1), 5_000_000).unwrap());
        assert_eq!(position.load(Ordering::Relaxed), 90_000_000);
        assert!(set_position(&client, key, u64::MAX).unwrap());
        assert_eq!(position.load(Ordering::Relaxed), 119_999_999);
        changed.store(true, Ordering::Relaxed);
        assert!(!set_position(&client, key, 3_000_000).unwrap());
        let new_info = now_playing(&client).unwrap();
        let new_key = u64::from_str_radix(new_info["seekKey"].as_str().unwrap(), 16).unwrap();
        assert_ne!(new_key, key);
        // Firefox can seek without providing mpris:length. Do not clamp all targets to zero.
        length.store(0, Ordering::Relaxed);
        let unknown = now_playing(&client).unwrap();
        assert_eq!(unknown["durationMs"], 0);
        assert_eq!(unknown["canSeek"], true);
        let unknown_key = u64::from_str_radix(unknown["seekKey"].as_str().unwrap(), 16).unwrap();
        for target in [30_000_000, 40_000_000, 25_000_000, 15_000_000] {
            assert!(set_position(&client, unknown_key, target).unwrap());
            assert_eq!(position.load(Ordering::Relaxed), target as i64);
        }
        seekable.store(false, Ordering::Relaxed);
        assert!(!set_position(&client, unknown_key, 5_000_000).unwrap());
        drop(service);
        assert!(now_playing(&client).is_none());
    }
    #[cfg(unix)]
    #[test]
    fn media_identity_cannot_read_arbitrary_paths() {
        assert!(app_icon("../../etc/passwd").is_empty());
        assert!(app_icon("/etc/passwd").is_empty());
    }
}
