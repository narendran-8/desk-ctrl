//! Phone plugged in with a USB cable: found and connected with no QR code.
//!
//! The agent polls `adb devices`. A phone that has allowed this computer (USB debugging) gets
//! two things, once, when it appears:
//!  1. `adb reverse tcp:PORT tcp:PORT`: port PORT on the phone's own localhost now leads to this
//!     agent, so the app reaches it with no network at all;
//!  2. a `deskctrl://pair/TOKEN?usb=1&port=PORT&name=HOST` link, started on the phone with
//!     `am start`. The app opens, adds this computer and connects over the cable.
//! The tunnel is checked every poll and put back if it was lost (adb restarted, ...). Needs the
//! `adb` program (package android-tools-adb) and USB debugging on the phone.

use crate::server::SharedState;
use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

pub const APP_ID: &str = "com.deskctrl.deskctrl";

#[derive(Clone, Default)]
pub struct UsbPhone {
    pub serial: String,
    pub model: String,
}

#[derive(Clone, Default)]
pub struct UsbStatus {
    /// Phones that are plugged in and paired.
    pub phones: Vec<UsbPhone>,
    /// What to do when a phone is plugged in but cannot be used yet.
    pub hint: Option<String>,
}

/// `adb`; on Windows an `adb.exe` next to the agent is preferred (unzip the platform-tools there).
fn default_adb() -> String {
    #[cfg(windows)]
    if let Some(next_to_us) = std::env::current_exe().ok().and_then(|e| e.parent().map(|d| d.join("adb.exe"))) {
        if next_to_us.is_file() {
            return next_to_us.to_string_lossy().into_owned();
        }
    }
    "adb".into()
}

pub struct Adb {
    pub program: String,
}

impl Adb {
    pub fn system() -> Self {
        Self { program: std::env::var("DESK_ADB").unwrap_or_else(|_| default_adb()) }
    }

    /// Runs `adb args...`: Some((success, stdout)), or None when adb cannot be started.
    /// Gives up (and kills it) after `limit` so a stuck adb never freezes the agent.
    pub fn run(&self, args: &[&str], limit: Duration) -> Option<(bool, String)> {
        let mut cmd = Command::new(&self.program);
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x0800_0000); // no console window
        }
        let mut child = cmd
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .ok()?;
        let end = Instant::now() + limit;
        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    let mut out = String::new();
                    if let Some(mut o) = child.stdout.take() {
                        let _ = o.read_to_string(&mut out);
                    }
                    return Some((status.success(), out));
                }
                Ok(None) if Instant::now() < end => thread::sleep(Duration::from_millis(30)),
                _ => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Some((false, String::new()));
                }
            }
        }
    }
}

#[derive(Debug, PartialEq, Default)]
pub struct Devices {
    /// (serial, model) of phones that allowed this computer.
    pub ready: Vec<(String, String)>,
    /// Plugged in, but the "Allow USB debugging?" question has not been answered yes.
    pub unauthorized: bool,
}

/// Reads the output of `adb devices -l`.
pub fn parse_devices(text: &str) -> Devices {
    let mut d = Devices::default();
    for line in text.lines().skip(1) {
        let mut parts = line.split_whitespace();
        let (Some(serial), Some(state)) = (parts.next(), parts.next()) else { continue };
        match state {
            "device" => {
                let model = parts
                    .find_map(|p| p.strip_prefix("model:"))
                    .map(|m| m.replace('_', " "))
                    .unwrap_or_else(|| serial.to_string());
                d.ready.push((serial.to_string(), model));
            }
            "unauthorized" => d.unauthorized = true,
            _ => {}
        }
    }
    d
}

/// The name shown on the phone: this computer's host name, reduced to characters that are safe
/// inside a link and a shell command.
pub fn computer_name() -> String {
    let raw = host_name();
    let name: String = raw.chars().map(|c| if c.is_ascii_alphanumeric() || "-._".contains(c) { c } else { '_' }).collect();
    if name.is_empty() { "Computer".into() } else { name }
}

#[cfg(unix)]
fn host_name() -> String {
    let mut buf = [0u8; 256];
    // SAFETY: gethostname writes at most buf.len() bytes.
    let ok = unsafe { libc::gethostname(buf.as_mut_ptr() as *mut libc::c_char, buf.len()) } == 0;
    if ok {
        let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
        String::from_utf8_lossy(&buf[..end]).to_string()
    } else {
        String::new()
    }
}

#[cfg(windows)]
fn host_name() -> String {
    std::env::var("COMPUTERNAME").unwrap_or_default()
}

pub fn pair_link(token: &str, port: u16, name: &str) -> String {
    format!("deskctrl://pair/{token}?usb=1&port={port}&name={name}&id={}", crate::identity::computer_id())
}

const SHORT: Duration = Duration::from_secs(8);

/// Tunnel + pairing link for one phone. Err says which step failed.
pub fn attach(adb: &Adb, serial: &str, port: u16, token: &str, name: &str) -> Result<(), String> {
    let p = format!("tcp:{port}");
    match adb.run(&["-s", serial, "reverse", &p, &p], SHORT) {
        Some((true, _)) => {}
        _ => return Err("could not set up the USB tunnel (adb reverse)".into()),
    }
    let cmd = format!(
        "am start -a android.intent.action.VIEW -p {APP_ID} -d '{}'",
        pair_link(token, port, name)
    );
    match adb.run(&["-s", serial, "shell", &cmd], SHORT) {
        Some((true, out)) if !out.contains("Error") => Ok(()),
        _ => Err("the ViL app could not be opened on the phone (is it installed?)".into()),
    }
}

fn tunnel_present(adb: &Adb, serial: &str, port: u16) -> bool {
    adb.run(&["-s", serial, "reverse", "--list"], SHORT)
        .is_some_and(|(_, out)| out.contains(&format!("tcp:{port}")))
}

/// One look at the cable. `known` are the phones already handled.
pub fn poll_once(adb: &Adb, shared: &SharedState, port: u16, known: &mut HashMap<String, String>) {
    let Some((_, out)) = adb.run(&["devices", "-l"], Duration::from_secs(12)) else {
        let mut s = shared.lock().unwrap();
        let how = if cfg!(windows) {
            "Put adb.exe (Android platform-tools) next to desk_ctrl_agent.exe, or add it to PATH"
        } else {
            "Install it: sudo apt install adb"
        };
        if s.usb.hint.is_none() {
            s.log(format!("USB: 'adb' was not found, so phones plugged in cannot be connected. {how}"));
        }
        s.usb.hint = Some(if cfg!(windows) {
            format!("To connect a phone by USB cable: {how}.")
        } else {
            "Install adb to connect a phone by USB:  sudo apt install adb".into()
        });
        return;
    };
    let devices = parse_devices(&out);
    let (token, name) = (shared.lock().unwrap().token.clone(), computer_name());

    let present: HashSet<&String> = devices.ready.iter().map(|(s, _)| s).collect();
    for (serial, model) in &devices.ready {
        if !known.contains_key(serial) {
            match attach(adb, serial, port, &token, &name) {
                Ok(()) => {
                    known.insert(serial.clone(), model.clone());
                    shared.lock().unwrap().log(format!("USB: {model} plugged in - paired and connected over the cable"));
                }
                Err(e) => {
                    // Not remembered: tried again on the next look.
                    shared.lock().unwrap().usb.hint = Some(format!("{model}: {e}"));
                    continue;
                }
            }
        } else if !tunnel_present(adb, serial, port) {
            let p = format!("tcp:{port}");
            if adb.run(&["-s", serial, "reverse", &p, &p], SHORT).is_some_and(|(ok, _)| ok) {
                shared.lock().unwrap().log(format!("USB: tunnel to {model} restored"));
            }
        }
    }
    let gone: Vec<String> = known.keys().filter(|s| !present.contains(s)).cloned().collect();
    for serial in gone {
        let model = known.remove(&serial).unwrap_or_default();
        shared.lock().unwrap().log(format!("USB: {model} unplugged"));
    }

    let mut s = shared.lock().unwrap();
    s.usb.phones = known.iter().map(|(serial, model)| UsbPhone { serial: serial.clone(), model: model.clone() }).collect();
    if devices.unauthorized && known.is_empty() {
        s.usb.hint = Some(
            "A phone is plugged in but has not allowed this computer. Unlock it and tap Allow on \"Allow USB debugging?\".".into(),
        );
    } else if devices.ready.iter().all(|(s2, _)| known.contains_key(s2)) {
        s.usb.hint = None;
    }
}

/// Watches the cable until `stop`. `enabled` is the "auto-connect USB phones" switch.
pub fn spawn(stop: Arc<AtomicBool>, shared: SharedState, port: u16, enabled: Arc<AtomicBool>) -> JoinHandle<()> {
    thread::spawn(move || {
        let adb = Adb::system();
        let mut known: HashMap<String, String> = HashMap::new();
        let mut last = Instant::now() - Duration::from_secs(10);
        while !stop.load(Ordering::Relaxed) {
            if last.elapsed() >= Duration::from_secs(2) {
                last = Instant::now();
                if enabled.load(Ordering::Relaxed) {
                    poll_once(&adb, &shared, port, &mut known);
                } else if !known.is_empty() {
                    known.clear();
                    let mut s = shared.lock().unwrap();
                    s.usb = UsbStatus::default();
                }
            }
            thread::sleep(Duration::from_millis(100));
        }
        // Do not leave the port forwarded on phones after the agent stops.
        let p = format!("tcp:{port}");
        for serial in known.keys() {
            let _ = adb.run(&["-s", serial, "reverse", "--remove", &p], SHORT);
        }
        shared.lock().unwrap().usb = UsbStatus::default();
    })
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use crate::server::Shared;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::Mutex;

    #[test]
    fn reads_adb_devices_output() {
        let out = "List of devices attached\n\
                   863d0058304830363451066c2082bb device usb:1-2 product:lancelot model:Redmi_Note_9 device:merlin transport_id:3\n\
                   R5CT10ABCDE            unauthorized usb:1-3 transport_id:4\n\
                   emulator-5554          offline\n\
                   \n";
        let d = parse_devices(out);
        assert_eq!(d.ready, vec![("863d0058304830363451066c2082bb".to_string(), "Redmi Note 9".to_string())]);
        assert!(d.unauthorized);
        assert_eq!(parse_devices("List of devices attached\n\n"), Devices::default());
        assert_eq!(parse_devices("").ready.len(), 0);
    }

    #[test]
    fn the_pairing_link_is_what_the_app_expects() {
        assert_eq!(
            pair_link("abc123", 8765, "my-pc"),
            format!("deskctrl://pair/abc123?usb=1&port=8765&name=my-pc&id={}", crate::identity::computer_id())
        );
        let n = computer_name();
        assert!(!n.is_empty() && n.chars().all(|c| c.is_ascii_alphanumeric() || "-._".contains(c)), "safe in a shell: {n}");
    }

    /// A stand-in for `adb`: prints what the test put in `devices.txt` / `reverse.txt` and
    /// records every call in `calls.log`.
    struct FakeAdb {
        dir: PathBuf,
    }

    impl FakeAdb {
        fn new(name: &str) -> Self {
            let dir = std::env::temp_dir().join(format!("deskctrl-adb-{name}-{}", std::process::id()));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(&dir).unwrap();
            let script = format!(
                r#"#!/bin/sh
D="{d}"
echo "$@" >> "$D/calls.log"
case "$*" in
  "devices -l") cat "$D/devices.txt" ;;
  *"reverse --list"*) cat "$D/reverse.txt" 2>/dev/null ;;
  *"reverse tcp:"*) echo "host tcp:8765 tcp:8765" > "$D/reverse.txt" ;;
  *"reverse --remove"*) rm -f "$D/reverse.txt" ;;
  *shell*) echo "Starting: Intent {{ act=android.intent.action.VIEW }}" ;;
esac
"#,
                d = dir.display()
            );
            let path = dir.join("adb");
            fs::write(&path, script).unwrap();
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
            Self { dir }
        }
        fn adb(&self) -> Adb {
            Adb { program: self.dir.join("adb").display().to_string() }
        }
        fn set_devices(&self, text: &str) {
            fs::write(self.dir.join("devices.txt"), text).unwrap();
        }
        fn calls(&self) -> Vec<String> {
            fs::read_to_string(self.dir.join("calls.log")).unwrap_or_default().lines().map(String::from).collect()
        }
        fn clear_calls(&self) {
            let _ = fs::remove_file(self.dir.join("calls.log"));
        }
        fn path(&self) -> &Path {
            &self.dir
        }
    }

    fn shared() -> SharedState {
        Arc::new(Mutex::new(Shared { token: "tok123".into(), ..Default::default() }))
    }

    const PHONE: &str = "List of devices attached\nSER1 device usb:1-2 model:Pixel_7 transport_id:1\n";

    #[test]
    fn a_plugged_in_phone_gets_the_tunnel_and_the_pairing_link_once() {
        let f = FakeAdb::new("attach");
        let sh = shared();
        let mut known = HashMap::new();
        f.set_devices(PHONE);

        poll_once(&f.adb(), &sh, 8765, &mut known);
        let calls = f.calls();
        assert!(calls.iter().any(|c| c == "-s SER1 reverse tcp:8765 tcp:8765"), "tunnel: {calls:?}");
        let start = calls.iter().find(|c| c.contains("am start")).expect("the app was started");
        assert!(start.contains("-s SER1 shell"), "{start}");
        assert!(start.contains("-p com.deskctrl.deskctrl"), "{start}");
        assert!(
            start.contains(&format!(
                "-d 'deskctrl://pair/tok123?usb=1&port=8765&name={}&id={}'",
                computer_name(),
                crate::identity::computer_id()
            )),
            "{start}"
        );
        assert_eq!(sh.lock().unwrap().usb.phones.len(), 1);
        assert_eq!(sh.lock().unwrap().usb.phones[0].model, "Pixel 7");
        assert!(sh.lock().unwrap().log.iter().any(|l| l.contains("Pixel 7 plugged in")));

        // Still plugged in: nothing is repeated (the app is not opened again every 2 s).
        f.clear_calls();
        poll_once(&f.adb(), &sh, 8765, &mut known);
        assert!(!f.calls().iter().any(|c| c.contains("am start")), "no second pairing: {:?}", f.calls());
        assert!(!f.calls().iter().any(|c| c.contains("reverse tcp:")), "tunnel still there: {:?}", f.calls());
        fs::remove_dir_all(f.path()).unwrap();
    }

    #[test]
    fn a_lost_tunnel_is_put_back_without_opening_the_app_again() {
        let f = FakeAdb::new("restore");
        let sh = shared();
        let mut known = HashMap::new();
        f.set_devices(PHONE);
        poll_once(&f.adb(), &sh, 8765, &mut known);
        fs::remove_file(f.path().join("reverse.txt")).unwrap(); // e.g. adb was restarted
        f.clear_calls();
        poll_once(&f.adb(), &sh, 8765, &mut known);
        assert!(f.calls().iter().any(|c| c == "-s SER1 reverse tcp:8765 tcp:8765"), "{:?}", f.calls());
        assert!(!f.calls().iter().any(|c| c.contains("am start")));
        assert!(sh.lock().unwrap().log.iter().any(|l| l.contains("tunnel to Pixel 7 restored")));
        fs::remove_dir_all(f.path()).unwrap();
    }

    #[test]
    fn unplugging_and_plugging_in_again_pairs_again() {
        let f = FakeAdb::new("replug");
        let sh = shared();
        let mut known = HashMap::new();
        f.set_devices(PHONE);
        poll_once(&f.adb(), &sh, 8765, &mut known);
        f.set_devices("List of devices attached\n\n");
        poll_once(&f.adb(), &sh, 8765, &mut known);
        assert!(sh.lock().unwrap().usb.phones.is_empty());
        assert!(sh.lock().unwrap().log.iter().any(|l| l.contains("Pixel 7 unplugged")));

        f.clear_calls();
        f.set_devices(PHONE);
        poll_once(&f.adb(), &sh, 8765, &mut known);
        assert!(f.calls().iter().any(|c| c.contains("am start")), "paired again: {:?}", f.calls());
        fs::remove_dir_all(f.path()).unwrap();
    }

    #[test]
    fn a_phone_that_has_not_allowed_usb_debugging_gets_a_hint_and_nothing_else() {
        let f = FakeAdb::new("unauth");
        let sh = shared();
        let mut known = HashMap::new();
        f.set_devices("List of devices attached\nSER9 unauthorized usb:1-3\n");
        poll_once(&f.adb(), &sh, 8765, &mut known);
        assert!(sh.lock().unwrap().usb.hint.as_deref().unwrap().contains("Allow"));
        assert!(!f.calls().iter().any(|c| c.contains("reverse")));
        assert!(sh.lock().unwrap().usb.phones.is_empty());
        fs::remove_dir_all(f.path()).unwrap();
    }

    #[test]
    fn without_adb_installed_it_says_how_to_get_it() {
        let sh = shared();
        let mut known = HashMap::new();
        poll_once(&Adb { program: "/nonexistent/adb".into() }, &sh, 8765, &mut known);
        assert!(sh.lock().unwrap().usb.hint.as_deref().unwrap().contains("apt install adb"));
    }

    #[test]
    fn the_app_not_being_installed_is_reported_and_retried() {
        let f = FakeAdb::new("noapp");
        // Make `am start` fail the way Android does.
        let script = fs::read_to_string(f.path().join("adb")).unwrap().replace("Starting: Intent {{ act=android.intent.action.VIEW }}", "Error: Activity not started");
        let script = script.replace("Starting: Intent { act=android.intent.action.VIEW }", "Error: Activity not started");
        fs::write(f.path().join("adb"), script).unwrap();
        let sh = shared();
        let mut known = HashMap::new();
        f.set_devices(PHONE);
        poll_once(&f.adb(), &sh, 8765, &mut known);
        assert!(known.is_empty(), "not remembered, so it is tried again");
        assert!(sh.lock().unwrap().usb.hint.as_deref().unwrap().contains("could not be opened"));
        fs::remove_dir_all(f.path()).unwrap();
    }
}
