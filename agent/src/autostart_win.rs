//! "Start the agent when I log in" on Windows: a value in the current user's `Run` registry key,
//! `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, named `DeskCtrlAgent`. The value is the
//! setting: switched on = it exists, switched off = it is deleted. No admin rights needed.
//! (The Linux agent writes an XDG autostart file instead, see autostart.rs.)

use std::io;
use std::path::{Path, PathBuf};
use windows_sys::Win32::Foundation::ERROR_SUCCESS;
use windows_sys::Win32::System::Registry::*;

/// The flag that starts the window already minimised (see main.rs).
pub const MINIMIZED_FLAG: &str = "--minimized";
const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const VALUE: &str = "DeskCtrlAgent";

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn check(code: u32) -> io::Result<()> {
    if code == ERROR_SUCCESS { Ok(()) } else { Err(io::Error::from_raw_os_error(code as i32)) }
}

/// The command the entry runs: the program in quotes (paths have spaces), then the flag.
pub fn command_line(exe: &Path, minimized: bool) -> String {
    let mut line = format!("\"{}\"", exe.display());
    if minimized {
        line.push(' ');
        line.push_str(MINIMIZED_FLAG);
    }
    line
}

/// The program path inside the command line.
fn program_of(line: &str) -> &str {
    match line.strip_prefix('"') {
        Some(rest) => rest.split('"').next().unwrap_or(""),
        None => line.split_whitespace().next().unwrap_or(""),
    }
}

fn open(write: bool) -> io::Result<HKEY> {
    let mut key: HKEY = std::ptr::null_mut();
    let access = if write { KEY_SET_VALUE | KEY_QUERY_VALUE } else { KEY_QUERY_VALUE };
    // SAFETY: valid NUL-terminated name, `key` is a valid out pointer.
    let code = unsafe {
        if write {
            RegCreateKeyExW(HKEY_CURRENT_USER, wide(RUN_KEY).as_ptr(), 0, std::ptr::null(), 0, access, std::ptr::null(), &mut key, std::ptr::null_mut())
        } else {
            RegOpenKeyExW(HKEY_CURRENT_USER, wide(RUN_KEY).as_ptr(), 0, access, &mut key)
        }
    };
    check(code)?;
    Ok(key)
}

fn read_value() -> Option<String> {
    let key = open(false).ok()?;
    let name = wide(VALUE);
    let mut size = 0u32;
    // SAFETY: first call only asks how long the value is.
    let code = unsafe { RegQueryValueExW(key, name.as_ptr(), std::ptr::null(), std::ptr::null_mut(), std::ptr::null_mut(), &mut size) };
    let result = if code == ERROR_SUCCESS && size >= 2 {
        let mut buf = vec![0u16; (size as usize).div_ceil(2)];
        let mut size2 = size;
        // SAFETY: `buf` holds `size` bytes.
        let code = unsafe { RegQueryValueExW(key, name.as_ptr(), std::ptr::null(), std::ptr::null_mut(), buf.as_mut_ptr() as *mut u8, &mut size2) };
        (code == ERROR_SUCCESS).then(|| {
            let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
            String::from_utf16_lossy(&buf[..end])
        })
    } else {
        None
    };
    // SAFETY: `key` was opened above.
    unsafe { RegCloseKey(key) };
    result
}

pub fn is_enabled() -> bool {
    read_value().is_some_and(|v| !v.trim().is_empty())
}

pub fn is_minimized() -> bool {
    read_value().is_some_and(|v| v.split_whitespace().any(|w| w == MINIMIZED_FLAG))
}

/// The program that is running now: what autostart should start.
pub fn current_exe() -> io::Result<PathBuf> {
    std::env::current_exe()
}

/// Switch autostart on (or change "minimised") for the program at `exe`.
pub fn enable(exe: &Path, minimized: bool) -> io::Result<()> {
    let key = open(true)?;
    let value: Vec<u8> = wide(&command_line(exe, minimized)).iter().flat_map(|c| c.to_le_bytes()).collect();
    // SAFETY: valid key, name and a REG_SZ buffer with its terminating NUL.
    let code = unsafe { RegSetValueExW(key, wide(VALUE).as_ptr(), 0, REG_SZ, value.as_ptr(), value.len() as u32) };
    // SAFETY: `key` was opened above.
    unsafe { RegCloseKey(key) };
    check(code)
}

/// Switch autostart off. Not being on already is fine.
pub fn disable() -> io::Result<()> {
    let Ok(key) = open(true) else { return Ok(()) };
    // SAFETY: valid key and name.
    let code = unsafe { RegDeleteValueW(key, wide(VALUE).as_ptr()) };
    // SAFETY: `key` was opened above.
    unsafe { RegCloseKey(key) };
    if code == ERROR_SUCCESS || code == windows_sys::Win32::Foundation::ERROR_FILE_NOT_FOUND { Ok(()) } else { check(code) }
}

/// At every start: if autostart is on but the program it names is gone (the agent was moved or
/// replaced), point it at this one. A program that still exists is left alone: another copy of the
/// agent (a test build) must not take over the user's autostart. Returns whether it was rewritten.
pub fn refresh(exe: &Path) -> bool {
    let Some(current) = read_value().filter(|v| !v.trim().is_empty()) else { return false };
    if Path::new(program_of(&current)).exists() {
        return false;
    }
    enable(exe, is_minimized()).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// The tests share one registry value.
    static REG: Mutex<()> = Mutex::new(());

    #[test]
    fn the_command_line_has_the_path_in_quotes() {
        let p = Path::new(r"C:\Program Files\DeskCtrl\desk_ctrl_agent.exe");
        assert_eq!(command_line(p, false), r#""C:\Program Files\DeskCtrl\desk_ctrl_agent.exe""#);
        assert_eq!(command_line(p, true), r#""C:\Program Files\DeskCtrl\desk_ctrl_agent.exe" --minimized"#);
        assert_eq!(program_of(&command_line(p, true)), r"C:\Program Files\DeskCtrl\desk_ctrl_agent.exe");
        assert_eq!(program_of(r"C:\a\b.exe --x"), r"C:\a\b.exe");
    }

    #[test]
    fn on_off_and_minimised_follow_the_registry_value() {
        let _g = REG.lock().unwrap_or_else(|e| e.into_inner());
        disable().unwrap();
        assert!(!is_enabled());
        enable(Path::new(r"C:\Apps\agent.exe"), true).unwrap();
        assert!(is_enabled() && is_minimized());
        enable(Path::new(r"C:\Apps\agent.exe"), false).unwrap();
        assert!(is_enabled() && !is_minimized());
        disable().unwrap();
        assert!(!is_enabled());
        disable().unwrap(); // already off: no error
    }

    #[test]
    fn a_moved_agent_is_pointed_at_again_but_another_working_copy_does_not_take_over() {
        let _g = REG.lock().unwrap_or_else(|e| e.into_inner());
        disable().unwrap();
        assert!(!refresh(Path::new(r"C:\New\agent.exe")), "off: nothing to fix");
        enable(Path::new(r"C:\Gone Apps\agent.exe"), true).unwrap();
        assert!(refresh(Path::new(r"C:\New\agent.exe")));
        assert_eq!(read_value().unwrap(), r#""C:\New\agent.exe" --minimized"#);
        // A program that exists (this test's own exe) is left alone.
        let me = std::env::current_exe().unwrap();
        enable(&me, false).unwrap();
        assert!(!refresh(Path::new(r"C:\Demo\agent.exe")));
        assert!(read_value().unwrap().contains(&me.display().to_string()));
        disable().unwrap();
    }
}
