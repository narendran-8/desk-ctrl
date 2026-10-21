//! Wire protocol (binary, big-endian):
//!   0x01 KEY_DOWN   u16 hid_usage
//!   0x02 KEY_UP     u16 hid_usage
//!   0x03 MOUSE_MOVE i16 dx, i16 dy
//!   0x04 MOUSE_BTN  u8 button (0=left,1=right,2=middle), u8 down
//!   0x05 SCROLL     i16 dx, i16 dy
//!
//! Key codes are USB HID keyboard usages (< 0x100). Media and system keys use
//! 0x8000 | HID consumer usage (0x8F01 = microphone mute, which has no usage).

#[derive(Debug, Clone, Copy)]
pub enum Event {
    Key { hid: u16, down: bool },
    Move { dx: i16, dy: i16 },
    Button { button: u8, down: bool },
    Scroll { dx: i16, dy: i16 },
}

pub fn parse(d: &[u8]) -> Option<Event> {
    let i16_at = |o: usize| Some(i16::from_be_bytes([*d.get(o)?, *d.get(o + 1)?]));
    match *d.first()? {
        t @ (0x01 | 0x02) => Some(Event::Key {
            hid: u16::from_be_bytes([*d.get(1)?, *d.get(2)?]),
            down: t == 0x01,
        }),
        0x03 => Some(Event::Move { dx: i16_at(1)?, dy: i16_at(3)? }),
        0x04 => Some(Event::Button { button: *d.get(1)?, down: *d.get(2)? != 0 }),
        0x05 => Some(Event::Scroll { dx: i16_at(1)?, dy: i16_at(3)? }),
        _ => None,
    }
}

/// USB HID usage ID -> Linux evdev key code.
#[cfg_attr(windows, allow(dead_code))]
pub fn hid_to_evdev(hid: u16) -> Option<u16> {
    Some(match hid {
        // letters a-z
        0x04..=0x1D => {
            const LETTERS: [u16; 26] = [
                30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, // a-m
                49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44, // n-z
            ];
            LETTERS[(hid - 0x04) as usize]
        }
        0x1E..=0x26 => hid - 0x1E + 2, // 1-9
        0x27 => 11,                    // 0
        0x28 => 28,                    // Enter
        0x29 => 1,                     // Esc
        0x2A => 14,                    // Backspace
        0x2B => 15,                    // Tab
        0x2C => 57,                    // Space
        0x2D => 12,                    // -
        0x2E => 13,                    // =
        0x2F => 26,                    // [
        0x30 => 27,                    // ]
        0x31 => 43,                    // backslash
        0x33 => 39,                    // ;
        0x34 => 40,                    // '
        0x35 => 41,                    // `
        0x36 => 51,                    // ,
        0x37 => 52,                    // .
        0x38 => 53,                    // /
        0x39 => 58,                    // Caps Lock
        0x3A..=0x43 => hid - 0x3A + 59, // F1-F10
        0x44 => 87,                    // F11
        0x45 => 88,                    // F12
        0x46 => 99,                    // PrintScreen
        0x47 => 70,                    // Scroll Lock
        0x48 => 119,                   // Pause
        0x49 => 110,                   // Insert
        0x4A => 102,                   // Home
        0x4B => 104,                   // PageUp
        0x4C => 111,                   // Delete
        0x4D => 107,                   // End
        0x4E => 109,                   // PageDown
        0x4F => 106,                   // Right
        0x50 => 105,                   // Left
        0x51 => 108,                   // Down
        0x52 => 103,                   // Up
        0x65 => 127,                   // Menu
        0xE0 => 29,                    // LCtrl
        0xE1 => 42,                    // LShift
        0xE2 => 56,                    // LAlt
        0xE3 => 125,                   // LSuper
        0xE4 => 97,                    // RCtrl
        0xE5 => 54,                    // RShift
        0xE6 => 100,                   // RAlt
        0xE7 => 126,                   // RSuper
        // media / system keys
        0x806F => 225, // brightness up
        0x8070 => 224, // brightness down
        0x80E2 => 113, // mute
        0x80EA => 114, // volume down
        0x80E9 => 115, // volume up
        0x80B5 => 163, // next track
        0x80B6 => 165, // previous track
        0x80CD => 164, // play / pause
        0x8192 => 140, // calculator
        0x819E => 152, // lock screen
        0x8F01 => 248, // microphone mute
        _ => return None,
    })
}

/// USB HID usage -> Windows virtual-key code, and whether the key is an "extended" one (the grey
/// keys next to the main block: arrows, Insert ... and the right-hand Ctrl / Alt / Win).
/// Brightness, microphone mute and lock have no key on Windows (see inject.rs for lock).
#[cfg_attr(not(windows), allow(dead_code))]
pub fn hid_to_vk(hid: u16) -> Option<(u16, bool)> {
    let plain = |vk: u16| Some((vk, false));
    let ext = |vk: u16| Some((vk, true));
    match hid {
        0x04..=0x1D => plain(0x41 + (hid - 0x04)), // a-z
        0x1E..=0x26 => plain(0x31 + (hid - 0x1E)), // 1-9
        0x27 => plain(0x30),                       // 0
        0x28 => plain(0x0D),                       // Enter
        0x29 => plain(0x1B),                       // Esc
        0x2A => plain(0x08),                       // Backspace
        0x2B => plain(0x09),                       // Tab
        0x2C => plain(0x20),                       // Space
        0x2D => plain(0xBD),                       // -
        0x2E => plain(0xBB),                       // =
        0x2F => plain(0xDB),                       // [
        0x30 => plain(0xDD),                       // ]
        0x31 => plain(0xDC),                       // backslash
        0x33 => plain(0xBA),                       // ;
        0x34 => plain(0xDE),                       // '
        0x35 => plain(0xC0),                       // `
        0x36 => plain(0xBC),                       // ,
        0x37 => plain(0xBE),                       // .
        0x38 => plain(0xBF),                       // /
        0x39 => plain(0x14),                       // Caps Lock
        0x3A..=0x45 => plain(0x70 + (hid - 0x3A)), // F1-F12
        0x46 => ext(0x2C),                         // Print Screen
        0x47 => plain(0x91),                       // Scroll Lock
        0x48 => plain(0x13),                       // Pause
        0x49 => ext(0x2D),                         // Insert
        0x4A => ext(0x24),                         // Home
        0x4B => ext(0x21),                         // Page Up
        0x4C => ext(0x2E),                         // Delete
        0x4D => ext(0x23),                         // End
        0x4E => ext(0x22),                         // Page Down
        0x4F => ext(0x27),                         // Right
        0x50 => ext(0x25),                         // Left
        0x51 => ext(0x28),                         // Down
        0x52 => ext(0x26),                         // Up
        0x65 => ext(0x5D),                         // Menu
        0xE0 => plain(0xA2),                       // left Ctrl
        0xE1 => plain(0xA0),                       // left Shift
        0xE2 => plain(0xA4),                       // left Alt
        0xE3 => ext(0x5B),                         // left Windows
        0xE4 => ext(0xA3),                         // right Ctrl
        0xE5 => plain(0xA1),                       // right Shift
        0xE6 => ext(0xA5),                         // right Alt
        0xE7 => ext(0x5C),                         // right Windows
        0x80E2 => ext(0xAD),                       // mute
        0x80EA => ext(0xAE),                       // volume down
        0x80E9 => ext(0xAF),                       // volume up
        0x80B5 => ext(0xB0),                       // next track
        0x80B6 => ext(0xB1),                       // previous track
        0x80CD => ext(0xB3),                       // play / pause
        0x8192 => ext(0xB7),                       // calculator (launch app 2)
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn media_keys_map_to_linux_codes() {
        assert_eq!(hid_to_evdev(0x806F), Some(225)); // KEY_BRIGHTNESSUP
        assert_eq!(hid_to_evdev(0x8070), Some(224)); // KEY_BRIGHTNESSDOWN
        assert_eq!(hid_to_evdev(0x80E9), Some(115)); // KEY_VOLUMEUP
        assert_eq!(hid_to_evdev(0x80CD), Some(164)); // KEY_PLAYPAUSE
        assert_eq!(hid_to_evdev(0x0004), Some(30)); // plain "a" still works
        assert_eq!(hid_to_evdev(0x8999), None);
    }

    #[test]
    fn keys_map_to_windows_virtual_keys() {
        assert_eq!(hid_to_vk(0x04), Some((0x41, false))); // A
        assert_eq!(hid_to_vk(0x1D), Some((0x5A, false))); // Z
        assert_eq!(hid_to_vk(0x1E), Some((0x31, false))); // 1
        assert_eq!(hid_to_vk(0x27), Some((0x30, false))); // 0
        assert_eq!(hid_to_vk(0x28), Some((0x0D, false))); // Enter
        assert_eq!(hid_to_vk(0x3A), Some((0x70, false))); // F1
        assert_eq!(hid_to_vk(0x45), Some((0x7B, false))); // F12
        assert_eq!(hid_to_vk(0x50), Some((0x25, true))); // Left arrow is an extended key
        assert_eq!(hid_to_vk(0xE3), Some((0x5B, true))); // Windows key
        assert_eq!(hid_to_vk(0x80E9), Some((0xAF, true))); // volume up
        assert_eq!(hid_to_vk(0x806F), None); // brightness: no key on Windows
        assert_eq!(hid_to_vk(0x8999), None);
    }

    #[test]
    fn every_key_the_linux_agent_knows_is_known_on_windows_too_except_the_ones_without_a_key() {
        for hid in (0x04u16..=0x52).chain([0x65, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7]) {
            if hid_to_evdev(hid).is_some() {
                assert!(hid_to_vk(hid).is_some(), "{hid:#x}");
            }
        }
        let without = [0x806F, 0x8070, 0x819E, 0x8F01];
        for hid in [0x80E2u16, 0x80EA, 0x80E9, 0x80B5, 0x80B6, 0x80CD, 0x8192, 0x806F, 0x8070, 0x819E, 0x8F01] {
            assert_eq!(hid_to_vk(hid).is_none(), without.contains(&hid), "{hid:#x}");
        }
    }

    #[test]
    fn key_frames_carry_the_full_16_bit_code() {
        match parse(&[0x01, 0x80, 0x6F]) {
            Some(Event::Key { hid: 0x806F, down: true }) => {}
            other => panic!("unexpected {other:?}"),
        }
    }
}
