//! Now-playing feedback, independent of audio streaming and input injection.
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;

pub const FRAME: u8 = 0x16;

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
) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        #[cfg(unix)]
        let bus = zbus::blocking::connection::Builder::session()
            .ok()
            .and_then(|b| b.method_timeout(Duration::from_millis(250)).build().ok());
        let mut previous = serde_json::Value::Null;
        let mut ticks = 0;
        while !stop.load(Ordering::Relaxed) {
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
                std::thread::sleep(Duration::from_millis(100));
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
        let value = serde_json::json!({"title":title.chars().take(512).collect::<String>(), "app":app, "playing":status == "Playing", "icon": app_icon(&desktop)});
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
    #[cfg(unix)]
    struct MockPlayer;
    #[cfg(unix)]
    #[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
    impl MockPlayer {
        #[zbus(property)]
        fn playback_status(&self) -> &str {
            "Playing"
        }
        #[zbus(property)]
        fn metadata(&self) -> std::collections::HashMap<String, zbus::zvariant::OwnedValue> {
            std::collections::HashMap::from([(
                "xesam:title".into(),
                zbus::zvariant::Value::from("A Firefox video 🎵")
                    .try_to_owned()
                    .unwrap(),
            )])
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
        let service = zbus::blocking::connection::Builder::address(address.trim())
            .unwrap()
            .name("org.mpris.MediaPlayer2.viltest")
            .unwrap()
            .serve_at("/org/mpris/MediaPlayer2", MockPlayer)
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
            let bytes = base64::engine::general_purpose::STANDARD.decode(encoded).unwrap();
            let icon = image::load_from_memory(&bytes).unwrap();
            assert!(icon.width() <= 24 && icon.height() <= 24);
        }
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
