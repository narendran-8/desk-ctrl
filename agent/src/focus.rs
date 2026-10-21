//! Tells the phone when a text field gets the keyboard focus on this computer, so it can
//! switch to its keyboard screen by itself.
//!
//! Uses the desktop's accessibility bus (AT-SPI): apps announce which widget has focus,
//! and the agent looks at whether that widget is editable. Switching accessibility on makes
//! apps start announcing; it is turned off again when the agent stops if we were the ones
//! to turn it on. Computers without an accessibility bus simply never send the event.
//!
//! Wire format, agent -> phone: `[0x13, 1]` focus landed on something you can type into,
//! `[0x13, 0]` it landed on something you cannot (older agents send just `[0x13]`, meaning 1).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use zbus::blocking::{connection, Connection, Proxy};
use zbus::zvariant::{OwnedObjectPath, Value};

pub const FRAME_ID: u8 = 0x13;

/// STATE_EDITABLE in AT-SPI's state set.
const EDITABLE: u32 = 7;

/// Whether an AT-SPI state set (two u32 words) contains `state`.
pub fn has_state(words: &[u32], state: u32) -> bool {
    words.get((state / 32) as usize).is_some_and(|w| w & (1 << (state % 32)) != 0)
}

/// Widgets you type into even though they are not flagged editable (a terminal takes typing).
const TYPEABLE_ROLES: &[&str] = &["terminal", "entry", "password text", "editbar", "spin button", "combo box"];

pub fn typeable_role(name: &str) -> bool {
    TYPEABLE_ROLES.contains(&name)
}

/// Window classes (X11 `WM_CLASS`) of programs you type into, for apps that tell the
/// desktop nothing about their focus.
const TYPEABLE_WINDOWS: &[&str] = &[
    "terminal", "xterm", "konsole", "alacritty", "kitty", "wezterm", "tilix", "terminator", "urxvt", "foot",
    "mousepad", "gedit", "xed", "kate", "kwrite", "pluma", "leafpad", "geany", "notepad", "code", "sublime",
    "emacs", "gvim", "libreoffice", "soffice", "abiword", "writer", "typora", "obsidian", "zeditor",
];

pub fn typeable_window(class: &str) -> bool {
    let c = class.to_lowercase();
    TYPEABLE_WINDOWS.iter().any(|w| c.contains(w))
}

fn typeable(bus: &Connection, sender: &str, path: &OwnedObjectPath) -> bool {
    let proxy = |iface: &'static str| Proxy::new(bus, sender.to_string(), path.clone(), iface).ok();
    let Some(p) = proxy("org.a11y.atspi.Accessible") else { return false };
    if p.call::<_, _, Vec<u32>>("GetState", &()).is_ok_and(|w| has_state(&w, EDITABLE)) {
        return true;
    }
    p.call::<_, _, String>("GetRoleName", &()).is_ok_and(|r| typeable_role(&r))
}

/// Connects to the accessibility bus; None when the desktop has none.
fn a11y_bus(session: &Connection) -> Option<(Connection, Option<Proxy<'static>>, bool)> {
    let bus = Proxy::new(session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus").ok()?;
    let addr: String = bus.call("GetAddress", &()).ok()?;
    let a11y = connection::Builder::address(addr.as_str()).ok()?.build().ok()?;
    let status = Proxy::new(session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status").ok()?;
    let was_on = status.get_property::<bool>("IsEnabled").unwrap_or(true);
    if !was_on {
        let _ = status.set_property("IsEnabled", true);
    }
    Some((a11y, Some(status), was_on))
}

/// The window in front (X11 only).
struct Window {
    id: String,
    class: String,
    pid: Option<u32>,
}

fn active_window() -> Option<Window> {
    let out = std::process::Command::new("xprop").args(["-root", "_NET_ACTIVE_WINDOW"]).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    let id = text.split('#').nth(1)?.split(|c: char| c == ',' || c.is_whitespace()).find(|t| t.starts_with("0x"))?.to_string();
    if id == "0x0" {
        return None;
    }
    let out = std::process::Command::new("xprop").args(["-id", &id, "WM_CLASS", "_NET_WM_PID"]).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    let mut class = String::new();
    let mut pid = None;
    for line in text.lines() {
        if let Some(v) = line.strip_prefix("WM_CLASS") {
            class = v.split('=').nth(1).unwrap_or("").trim().to_string();
        } else if let Some(v) = line.strip_prefix("_NET_WM_PID") {
            pid = v.split('=').nth(1).and_then(|n| n.trim().parse().ok());
        }
    }
    Some(Window { id, class, pid })
}

const ACTIVE: u32 = 1;
const FOCUSED: u32 = 12;

type Child = (String, OwnedObjectPath);

fn children(bus: &Connection, who: &Child) -> Vec<Child> {
    Proxy::new(bus, who.0.clone(), who.1.clone(), "org.a11y.atspi.Accessible")
        .ok()
        .and_then(|p| p.call::<_, _, Vec<Child>>("GetChildren", &()).ok())
        .unwrap_or_default()
}

fn state_of(bus: &Connection, who: &Child) -> Vec<u32> {
    Proxy::new(bus, who.0.clone(), who.1.clone(), "org.a11y.atspi.Accessible")
        .ok()
        .and_then(|p| p.call::<_, _, Vec<u32>>("GetState", &()).ok())
        .unwrap_or_default()
}

/// What has the keyboard focus inside the program with process id `pid`, which is in front:
/// `Some(true)` something you can type into, `Some(false)` something else (or nothing),
/// `None` when it cannot be told (the program does not use accessibility, or its tree is too big
/// to search in time).
fn focused_in(bus: &Connection, pid: u32, names: &mut std::collections::HashMap<String, u32>) -> Option<bool> {
    let root: Child = ("org.a11y.atspi.Registry".into(), OwnedObjectPath::try_from("/org/a11y/atspi/accessible/root").ok()?);
    let dbus = Proxy::new(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus").ok()?;
    let mut verdict = None;
    for app in children(bus, &root) {
        let app_pid = match names.get(&app.0) {
            Some(p) => *p,
            None => {
                let p = dbus.call::<_, _, u32>("GetConnectionUnixProcessID", &(app.0.as_str(),)).unwrap_or(0);
                names.insert(app.0.clone(), p);
                p
            }
        };
        if app_pid != pid {
            continue;
        }
        // Only the window that is active (a browser may have many).
        let windows: Vec<Child> = children(bus, &app).into_iter().filter(|w| has_state(&state_of(bus, w), ACTIVE)).collect();
        if windows.is_empty() {
            continue;
        }
        let started = Instant::now();
        let mut queue: std::collections::VecDeque<Child> = windows.into();
        let mut seen = 0;
        while let Some(node) = queue.pop_front() {
            seen += 1;
            if seen > 800 || started.elapsed() > Duration::from_millis(300) {
                return verdict; // too big: inconclusive
            }
            if has_state(&state_of(bus, &node), FOCUSED) {
                return Some(typeable(bus, &node.0, &node.1));
            }
            queue.extend(children(bus, &node));
        }
        // A tree this small says nothing (an app that does not really expose its widgets).
        verdict = if seen >= 8 { Some(false) } else { verdict };
    }
    verdict
}

/// `on_focus(true)` when the focus lands somewhere you can type, `on_focus(false)` when it
/// lands somewhere you cannot, so the phone always knows where the focus is now.
pub fn spawn(stop: Arc<AtomicBool>, on_focus: impl Fn(bool) + Send + Sync + 'static) -> JoinHandle<()> {
    let on_focus = Arc::new(on_focus);
    let last = Arc::new(std::sync::Mutex::new((false, Instant::now() - Duration::from_secs(5))));
    let fire = {
        let (on_focus, last) = (on_focus.clone(), last.clone());
        move |typeable: bool, force: bool, why: &str| {
            let mut l = last.lock().unwrap();
            // The same answer twice in a row (two ways of noticing one focus change) is sent once,
            // unless a window was just switched to: that is always worth telling.
            if !force && l.0 == typeable && l.1.elapsed() < Duration::from_millis(400) {
                return;
            }
            *l = (typeable, Instant::now());
            if std::env::var_os("DESK_DEBUG").is_some() {
                eprintln!("focus typeable={typeable}: {why}");
            }
            on_focus(typeable);
        }
    };
    // Watch which window is in front, and what has the focus inside it. Switching windows or
    // browser tabs often sends no focus event, so the focus is looked up directly.
    let bus_slot: Arc<std::sync::Mutex<Option<Connection>>> = Arc::new(std::sync::Mutex::new(None));
    {
        let (stop, fire, bus_slot) = (stop.clone(), fire.clone(), bus_slot.clone());
        thread::spawn(move || {
            let mut shown = String::new();
            let mut told: Option<bool> = None;
            let mut names = std::collections::HashMap::new();
            while !stop.load(Ordering::Relaxed) {
                if let Some(w) = active_window() {
                    let changed = w.id != shown;
                    if changed {
                        shown = w.id.clone();
                        names.clear(); // programs come and go: look their process ids up again
                    }
                    let bus = bus_slot.lock().unwrap().clone();
                    let found = match (bus, w.pid) {
                        (Some(b), Some(pid)) => focused_in(&b, pid, &mut names),
                        _ => None,
                    };
                    // A program that cannot be asked: go by what kind of program it is.
                    let known = if changed { Some(found.unwrap_or_else(|| typeable_window(&w.class))) } else { found };
                    if let Some(state) = known {
                        if changed || told != Some(state) {
                            fire(state, changed, &format!("{} ({})", w.class, if changed { "window" } else { "focus" }));
                        }
                        told = Some(state);
                    }
                }
                thread::sleep(Duration::from_millis(400));
            }
        });
    }
    thread::spawn(move || {
        let Ok(session) = Connection::session() else { return };
        let Some((a11y, status, was_on)) = a11y_bus(&session) else { return };
        *bus_slot.lock().unwrap() = Some(a11y.clone());

        // Apps only announce focus once somebody has registered for it.
        if let Ok(reg) = Proxy::new(
            &a11y,
            "org.a11y.atspi.Registry",
            "/org/a11y/atspi/registry",
            "org.a11y.atspi.Registry",
        ) {
            let _ = reg.call::<_, _, ()>("RegisterEvent", &("object:state-changed:focused", Vec::<String>::new(), ""));
        }
        let rule = "type='signal',interface='org.a11y.atspi.Event.Object',member='StateChanged'";
        if let Ok(dbus) = Proxy::new(&a11y, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus") {
            let _ = dbus.call::<_, _, ()>("AddMatch", &(rule,));
        }

        // Read events on a helper thread so this one can notice `stop`.
        let (tx, rx) = std::sync::mpsc::channel::<(String, OwnedObjectPath)>();
        let reader = a11y.clone();
        thread::spawn(move || {
            for msg in zbus::blocking::MessageIterator::from(reader).flatten() {
                let h = msg.header();
                if h.member().map(|m| m.as_str()) != Some("StateChanged") {
                    continue;
                }
                let (Some(sender), Some(path)) = (h.sender(), h.path()) else { continue };
                let body = msg.body();
                // (kind: s, detail1: i, detail2: i, detail: v, props: a{sv})
                let Ok((kind, gained, _d2, _v, _p)) =
                    body.deserialize::<(String, i32, i32, Value, std::collections::HashMap<String, Value>)>()
                else {
                    continue;
                };
                if kind == "focused" && gained == 1 && tx.send((sender.to_string(), path.to_owned().into())).is_err() {
                    break;
                }
            }
        });

        while !stop.load(Ordering::Relaxed) {
            if let Ok((sender, path)) = rx.recv_timeout(Duration::from_millis(300)) {
                fire(typeable(&a11y, &sender, &path), false, &format!("field {sender}"));
            }
        }
        if !was_on {
            if let Some(s) = status {
                let _ = s.set_property("IsEnabled", false);
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_state_bits() {
        assert!(has_state(&[1 << 7, 0], EDITABLE));
        assert!(!has_state(&[1 << 6, 0], EDITABLE));
        assert!(has_state(&[0, 1], 32), "second word");
        assert!(!has_state(&[], EDITABLE));
    }
}

#[cfg(test)]
mod more_tests {
    use super::*;

    #[test]
    fn knows_typeable_roles_and_windows() {
        assert!(typeable_role("terminal"));
        assert!(typeable_role("entry"));
        assert!(!typeable_role("push button"));
        assert!(!typeable_role("label"));
        assert!(typeable_window("\"xfce4-terminal\", \"Xfce4-terminal\""));
        assert!(typeable_window("\"mousepad\", \"Mousepad\""));
        assert!(!typeable_window("\"thunar\", \"Thunar\""));
        assert!(!typeable_window("\"brave-browser\", \"Brave-browser\""));
    }
}
