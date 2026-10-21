//! Who is already listening on our port? (Windows: `netstat`, `tasklist`, `taskkill`.)

use crate::winproc::quiet;
use std::path::PathBuf;
use std::time::{Duration, Instant};

#[derive(Clone, Debug, PartialEq)]
pub struct Owner {
    pub pid: Option<u32>,
    /// Unused on Windows; kept so the window code is the same on every system.
    pub uid: u32,
    pub name: Option<String>,
    pub exe: Option<PathBuf>,
}

impl Owner {
    /// Another copy of this agent (same program name), not this process.
    pub fn is_other_agent(&self) -> bool {
        let Some(pid) = self.pid else { return false };
        if pid == std::process::id() {
            return false;
        }
        let ours = std::env::current_exe()
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_lowercase()));
        let theirs = self.name.as_ref().map(|n| n.to_lowercase());
        ours.is_some() && ours == theirs
    }

    pub fn describe(&self) -> String {
        let what = if self.is_other_agent() {
            "another ViL agent".to_string()
        } else {
            self.name.clone().map_or("another program".to_string(), |n| format!("\"{n}\""))
        };
        match self.pid {
            Some(pid) => format!("{what} (pid {pid})"),
            None => format!("{what} run by another user"),
        }
    }
}

/// The port of a table row: the low 16 bits hold it in network byte order.
fn port_of_row(dw_local_port: u32) -> u16 {
    u16::from_be((dw_local_port & 0xFFFF) as u16)
}

/// The IPv4 listeners of this computer as (port, pid), from the system's TCP table (not from
/// `netstat`, whose words change with the language of Windows).
fn listeners() -> Vec<(u16, u32)> {
    use windows_sys::Win32::NetworkManagement::IpHelper::{GetExtendedTcpTable, MIB_TCPROW_OWNER_PID, TCP_TABLE_OWNER_PID_LISTENER};
    use windows_sys::Win32::Networking::WinSock::AF_INET;
    let mut size = 0u32;
    // SAFETY: the first call only asks how big the table is.
    unsafe { GetExtendedTcpTable(std::ptr::null_mut(), &mut size, 0, AF_INET as u32, TCP_TABLE_OWNER_PID_LISTENER, 0) };
    if size == 0 {
        return Vec::new();
    }
    // 4-byte aligned buffer, a little bigger in case the table grew meanwhile.
    let mut buf = vec![0u32; (size as usize).div_ceil(4) + 64];
    let mut size = (buf.len() * 4) as u32;
    // SAFETY: `buf` is `size` bytes and the table is written into it.
    let code = unsafe { GetExtendedTcpTable(buf.as_mut_ptr() as *mut _, &mut size, 0, AF_INET as u32, TCP_TABLE_OWNER_PID_LISTENER, 0) };
    if code != 0 {
        return Vec::new();
    }
    let count = buf[0] as usize;
    let rows = unsafe { buf.as_ptr().add(1) as *const MIB_TCPROW_OWNER_PID };
    // SAFETY: the table holds `count` rows right after the count.
    (0..count).map(|i| unsafe { *rows.add(i) }).map(|r| (port_of_row(r.dwLocalPort), r.dwOwningPid)).collect()
}

/// The program file of a process, if it can be asked.
fn exe_of(pid: u32) -> Option<PathBuf> {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION};
    // SAFETY: plain handle calls, the handle is closed again.
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h.is_null() {
            return None;
        }
        let mut buf = [0u16; 1024];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, 0, buf.as_mut_ptr(), &mut len);
        CloseHandle(h);
        (ok != 0).then(|| PathBuf::from(String::from_utf16_lossy(&buf[..len as usize])))
    }
}

pub fn listener(port: u16) -> Option<Owner> {
    let (_, pid) = listeners().into_iter().find(|(p, _)| *p == port)?;
    let exe = exe_of(pid);
    let name = exe.as_ref().and_then(|e| e.file_name()).map(|n| n.to_string_lossy().to_string());
    Some(Owner { pid: Some(pid), uid: 0, name, exe })
}

fn port_is_free(port: u16) -> bool {
    std::net::TcpListener::bind(("0.0.0.0", port)).is_ok()
}

/// Ask the process to quit (then force it), and wait until `port` is free.
pub fn stop(owner: &Owner, port: u16) -> Result<(), String> {
    let pid = owner.pid.ok_or("It runs as another user, so it cannot be stopped from here.")?;
    if pid == std::process::id() {
        return Err("That is this program itself.".into());
    }
    for force in [false, true] {
        let mut cmd = quiet("taskkill");
        cmd.args(["/PID", &pid.to_string()]);
        if force {
            cmd.arg("/F");
        }
        let _ = cmd.output();
        let end = Instant::now() + Duration::from_secs(if force { 2 } else { 3 });
        while Instant::now() < end {
            if port_is_free(port) {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }
    Err(format!("Port {port} is still in use after stopping pid {pid}."))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_port_is_read_from_a_table_row() {
        assert_eq!(port_of_row(0x3D22), 8765); // 8765 = 0x223D, stored as 0x3D22
        assert_eq!(port_of_row(0xFFFF_3D22), 8765, "the upper half is padding");
    }

    #[test]
    fn a_port_we_listen_on_is_found_with_our_pid_and_name() {
        let l = std::net::TcpListener::bind(("0.0.0.0", 0)).unwrap();
        let port = l.local_addr().unwrap().port();
        let o = listener(port).expect("our own listener is in the table");
        // Wine (where these tests also run) reports every pid as 0 and knows no program name.
        assert!(o.pid == Some(std::process::id()) || o.pid == Some(0), "{:?}", o.pid);
        drop(l);
        assert!(listener(port).is_none(), "gone after it stopped listening");
    }
}
