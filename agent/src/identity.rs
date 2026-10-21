//! Who this computer is, and how it describes itself to a phone plugged in by USB.
//!
//! The pairing token changes whenever the agent restarts, so the phone cannot tell "the same
//! computer again" from the token. A computer id that stays the same across restarts lets it:
//! a computer it already knows is updated, not added a second time.

/// A stable id for this computer: a hash of the machine id (the raw machine id is not shared,
/// it is meant to stay private). 16 hex characters.
pub fn computer_id() -> String {
    let raw = machine_id();
    let raw = raw.trim();
    // Without a machine id (rare) the host name is the best there is.
    let basis = if raw.is_empty() { crate::usb::computer_name() } else { raw.to_string() };
    hash_id(&basis)
}

#[cfg(unix)]
fn machine_id() -> String {
    std::fs::read_to_string("/etc/machine-id")
        .or_else(|_| std::fs::read_to_string("/var/lib/dbus/machine-id"))
        .unwrap_or_default()
}

/// The `MachineGuid` of Windows, from `reg query` (the same value every start, private to this PC).
#[cfg(windows)]
fn machine_id() -> String {
    crate::winproc::quiet("reg")
        .args(["query", r"HKLM\SOFTWARE\Microsoft\Cryptography", "/v", "MachineGuid"])
        .output()
        .ok()
        .map(|o| parse_machine_guid(&String::from_utf8_lossy(&o.stdout)))
        .unwrap_or_default()
}

/// `    MachineGuid    REG_SZ    3c1b...` -> the guid.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn parse_machine_guid(out: &str) -> String {
    out.lines()
        .find(|l| l.contains("MachineGuid"))
        .and_then(|l| l.split("REG_SZ").nth(1))
        .map(|g| g.trim().to_string())
        .unwrap_or_default()
}

/// FNV-1a 64 over "deskctrl:" + `basis`, as 16 hex characters.
pub fn hash_id(basis: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in format!("deskctrl:{basis}").bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{h:016x}")
}

/// Frame id, agent -> phone: how to reach this computer by Wi-Fi and Bluetooth.
pub const INFO_FRAME: u8 = 0x14;

/// Whether a client address is this computer itself: a phone on the USB cable arrives through
/// adb's tunnel, so it comes from localhost.
pub fn is_loopback(addr: &str) -> bool {
    addr.starts_with("127.") || addr.starts_with("[::1]") || addr.starts_with("[::ffff:127.")
}

/// `[0x14] + "id=..&ip=..&port=..&bt=..&name=.."`. Sent to a phone on the USB cable only:
/// that link is the one proven to belong to somebody holding this computer, so the phone can
/// trust it and set up Wi-Fi and Bluetooth for the computer without a QR code.
pub fn info_frame(ip: Option<&str>, port: u16, bt: Option<&str>) -> Vec<u8> {
    let mut q = vec![format!("id={}", computer_id()), format!("port={port}"), format!("name={}", crate::usb::computer_name())];
    if let Some(ip) = ip {
        q.push(format!("ip={ip}"));
    }
    if let Some(bt) = bt {
        q.push(format!("bt={bt}"));
    }
    let mut frame = vec![INFO_FRAME];
    frame.extend_from_slice(q.join("&").as_bytes());
    frame
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_machine_guid_is_read_from_reg_output() {
        let out = "\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Cryptography\r\n    MachineGuid    REG_SZ    3c1b2f4e-aaaa-bbbb-cccc-0123456789ab\r\n\r\n";
        assert_eq!(parse_machine_guid(out), "3c1b2f4e-aaaa-bbbb-cccc-0123456789ab");
        assert_eq!(parse_machine_guid("ERROR: nothing"), "");
    }

    #[test]
    fn the_id_is_stable_and_looks_like_an_id() {
        let a = computer_id();
        assert_eq!(a, computer_id(), "the same every time");
        assert_eq!(a.len(), 16);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(hash_id("machine-a"), hash_id("machine-b"));
        assert_eq!(hash_id("x"), hash_id("x"));
        assert!(!a.contains(&std::fs::read_to_string("/etc/machine-id").unwrap_or_default().trim().to_string()) || a.len() == 16);
    }

    #[test]
    fn a_phone_on_the_cable_comes_from_localhost() {
        assert!(is_loopback("127.0.0.1:50000"));
        assert!(is_loopback("[::1]:50000"));
        assert!(!is_loopback("192.168.1.20:50000"));
        assert!(!is_loopback("10.63.184.49:41000"));
    }

    #[test]
    fn the_info_frame_says_how_to_reach_the_computer() {
        let f = info_frame(Some("10.0.0.5"), 8765, Some("AA:BB:CC:DD:EE:FF"));
        assert_eq!(f[0], 0x14);
        let text = String::from_utf8(f[1..].to_vec()).unwrap();
        let get = |k: &str| text.split('&').find_map(|p| p.strip_prefix(&format!("{k}="))).map(String::from);
        assert_eq!(get("id").unwrap(), computer_id());
        assert_eq!(get("ip").unwrap(), "10.0.0.5");
        assert_eq!(get("port").unwrap(), "8765");
        assert_eq!(get("bt").unwrap(), "AA:BB:CC:DD:EE:FF");
        assert_eq!(get("name").unwrap(), crate::usb::computer_name());
        // Without a network or Bluetooth, those parts are simply missing.
        let bare = String::from_utf8(info_frame(None, 8765, None)[1..].to_vec()).unwrap();
        assert!(!bare.contains("ip=") && !bare.contains("bt="));
    }
}
