//! Input injection: Linux through /dev/uinput (works on X11 and Wayland), Windows through
//! `SendInput`. Both end in the same [`Sink`].

use crate::hid::Event;
#[cfg(unix)]
use crate::hid::hid_to_evdev;
#[cfg(unix)]
use evdev::uinput::{VirtualDevice, VirtualDeviceBuilder};
#[cfg(unix)]
use evdev::{AttributeSet, EventType, InputEvent, Key, RelativeAxisType};
use std::collections::HashSet;

/// Where decoded events end up. The real implementation is [`Injector`];
/// tests use a recorder.
pub trait Sink: Send {
    fn apply(&mut self, ev: Event) -> std::io::Result<()>;
}

/// Shared by every connected phone (Wi-Fi and Bluetooth alike). Remembers which
/// keys and buttons are held so they can be released if the last link drops
/// mid-press, instead of leaving a key stuck down.
pub struct Input {
    sink: Box<dyn Sink>,
    keys: HashSet<u16>,
    buttons: HashSet<u8>,
}

impl Input {
    pub fn new(sink: Box<dyn Sink>) -> Self {
        Self { sink, keys: HashSet::new(), buttons: HashSet::new() }
    }

    pub fn apply(&mut self, ev: Event) -> std::io::Result<()> {
        match ev {
            Event::Key { hid, down } => {
                if down {
                    self.keys.insert(hid);
                } else {
                    self.keys.remove(&hid);
                }
            }
            Event::Button { button, down } => {
                if down {
                    self.buttons.insert(button);
                } else {
                    self.buttons.remove(&button);
                }
            }
            _ => {}
        }
        self.sink.apply(ev)
    }

    pub fn release_all(&mut self) {
        for hid in self.keys.drain().collect::<Vec<_>>() {
            let _ = self.sink.apply(Event::Key { hid, down: false });
        }
        for button in self.buttons.drain().collect::<Vec<_>>() {
            let _ = self.sink.apply(Event::Button { button, down: false });
        }
    }
}

#[cfg(unix)]
pub struct Injector {
    dev: VirtualDevice,
}

#[cfg(unix)]
impl Injector {
    pub fn new() -> std::io::Result<Self> {
        let mut keys = AttributeSet::<Key>::new();
        for code in 1..256u16 {
            keys.insert(Key::new(code));
        }
        for btn in [Key::BTN_LEFT, Key::BTN_RIGHT, Key::BTN_MIDDLE] {
            keys.insert(btn);
        }
        let mut axes = AttributeSet::<RelativeAxisType>::new();
        for a in [
            RelativeAxisType::REL_X,
            RelativeAxisType::REL_Y,
            RelativeAxisType::REL_WHEEL,
            RelativeAxisType::REL_HWHEEL,
        ] {
            axes.insert(a);
        }
        let dev = VirtualDeviceBuilder::new()?
            .name("desk_ctrl virtual input")
            .with_keys(&keys)?
            .with_relative_axes(&axes)?
            .build()?;
        Ok(Self { dev })
    }
}

#[cfg(unix)]
impl Sink for Injector {
    fn apply(&mut self, ev: Event) -> std::io::Result<()> {
        let rel = |axis: RelativeAxisType, v: i16| InputEvent::new(EventType::RELATIVE, axis.0, v as i32);
        match ev {
            Event::Key { hid, down } => {
                if let Some(code) = hid_to_evdev(hid) {
                    self.dev.emit(&[InputEvent::new(EventType::KEY, code, down as i32)])?;
                }
            }
            Event::Move { dx, dy } => {
                self.dev.emit(&[rel(RelativeAxisType::REL_X, dx), rel(RelativeAxisType::REL_Y, dy)])?;
            }
            Event::Button { button, down } => {
                let key = match button {
                    0 => Key::BTN_LEFT,
                    1 => Key::BTN_RIGHT,
                    2 => Key::BTN_MIDDLE,
                    _ => return Ok(()),
                };
                self.dev.emit(&[InputEvent::new(EventType::KEY, key.code(), down as i32)])?;
            }
            Event::Scroll { dx, dy } => {
                self.dev.emit(&[
                    rel(RelativeAxisType::REL_HWHEEL, dx),
                    rel(RelativeAxisType::REL_WHEEL, dy),
                ])?;
            }
        }
        Ok(())
    }
}

// ---- Windows ---------------------------------------------------------------------------------

#[cfg(windows)]
pub struct Injector;

#[cfg(windows)]
impl Injector {
    pub fn new() -> std::io::Result<Self> {
        Ok(Self)
    }
}

#[cfg(windows)]
mod win {
    use crate::hid::hid_to_vk;
    use windows_sys::Win32::System::Shutdown::LockWorkStation;
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;

    /// The lock-screen key of the phone (HID consumer usage 0x19E).
    const LOCK: u16 = 0x819E;
    /// One scroll step = one notch of the wheel.
    const NOTCH: i32 = 120;

    fn send(input: INPUT) -> std::io::Result<()> {
        // SAFETY: one fully initialised INPUT, and its true size.
        let sent = unsafe { SendInput(1, &input, std::mem::size_of::<INPUT>() as i32) };
        if sent == 1 { Ok(()) } else { Err(std::io::Error::last_os_error()) }
    }

    pub fn key(hid: u16, down: bool) -> std::io::Result<()> {
        if hid == LOCK {
            if down {
                // SAFETY: no arguments; locks the screen of the logged-in user.
                unsafe { LockWorkStation() };
            }
            return Ok(());
        }
        let Some((vk, extended)) = hid_to_vk(hid) else { return Ok(()) };
        let mut flags = if down { 0 } else { KEYEVENTF_KEYUP };
        if extended {
            flags |= KEYEVENTF_EXTENDEDKEY;
        }
        send(INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_0 { ki: KEYBDINPUT { wVk: vk, wScan: 0, dwFlags: flags, time: 0, dwExtraInfo: 0 } },
        })
    }

    fn mouse(dx: i32, dy: i32, data: i32, flags: MOUSE_EVENT_FLAGS) -> std::io::Result<()> {
        send(INPUT {
            r#type: INPUT_MOUSE,
            Anonymous: INPUT_0 {
                mi: MOUSEINPUT { dx, dy, mouseData: data as u32, dwFlags: flags, time: 0, dwExtraInfo: 0 },
            },
        })
    }

    pub fn move_by(dx: i16, dy: i16) -> std::io::Result<()> {
        mouse(dx as i32, dy as i32, 0, MOUSEEVENTF_MOVE)
    }

    pub fn button(button: u8, down: bool) -> std::io::Result<()> {
        let flags = match (button, down) {
            (0, true) => MOUSEEVENTF_LEFTDOWN,
            (0, false) => MOUSEEVENTF_LEFTUP,
            (1, true) => MOUSEEVENTF_RIGHTDOWN,
            (1, false) => MOUSEEVENTF_RIGHTUP,
            (2, true) => MOUSEEVENTF_MIDDLEDOWN,
            (2, false) => MOUSEEVENTF_MIDDLEUP,
            _ => return Ok(()),
        };
        mouse(0, 0, 0, flags)
    }

    pub fn scroll(dx: i16, dy: i16) -> std::io::Result<()> {
        if dy != 0 {
            mouse(0, 0, dy as i32 * NOTCH, MOUSEEVENTF_WHEEL)?;
        }
        if dx != 0 {
            mouse(0, 0, dx as i32 * NOTCH, MOUSEEVENTF_HWHEEL)?;
        }
        Ok(())
    }
}

#[cfg(windows)]
impl Sink for Injector {
    fn apply(&mut self, ev: Event) -> std::io::Result<()> {
        match ev {
            Event::Key { hid, down } => win::key(hid, down),
            Event::Move { dx, dy } => win::move_by(dx, dy),
            Event::Button { button, down } => win::button(button, down),
            Event::Scroll { dx, dy } => win::scroll(dx, dy),
        }
    }
}
