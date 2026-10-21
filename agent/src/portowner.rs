//! Who is already listening on our port? Used when "Address already in use" stops the
//! agent from starting, so the window can say what holds the port and offer to stop it.
//! Reads /proc directly (no extra tools needed).

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

#[derive(Clone, Debug, PartialEq)]
pub struct Owner {
    /// None when the process can't be seen: it runs as another user, usually root (`sudo`).
    pub pid: Option<u32>,
    /// User the listening socket belongs to.
    pub uid: u32,
    pub name: Option<String>,
    pub exe: Option<PathBuf>,
}

impl Owner {
    /// Another copy of this agent (same program file), not this process.
    pub fn is_other_agent(&self) -> bool {
        let (Some(pid), Some(exe)) = (self.pid, &self.exe) else { return false };
        if pid == std::process::id() {
            return false;
        }
        let ours = std::env::current_exe().ok();
        let name = |p: &Path| p.file_name().map(|n| n.to_string_lossy().to_string());
        ours.as_deref().and_then(name).is_some_and(|n| Some(n) == name(exe))
    }

    pub fn describe(&self) -> String {
        let what = if self.is_other_agent() {
            "another ViL agent".to_string()
        } else {
            self.name.clone().map_or("another program".to_string(), |n| format!("\"{n}\""))
        };
        match self.pid {
            Some(pid) => format!("{what} (pid {pid})"),
            None if self.uid == 0 => format!("{what} running as root (probably started with sudo)"),
            None => format!("{what} run by another user"),
        }
    }
}

/// The process listening on TCP `port`, if any.
pub fn listener(port: u16) -> Option<Owner> {
    listener_in(Path::new("/proc"), port)
}

pub fn listener_in(proc: &Path, port: u16) -> Option<Owner> {
    for table in ["net/tcp", "net/tcp6"] {
        let Ok(text) = fs::read_to_string(proc.join(table)) else { continue };
        for line in text.lines().skip(1) {
            // sl local_address rem_address st tx:rx tr:when retrnsmt uid timeout inode ...
            let f: Vec<&str> = line.split_whitespace().collect();
            if f.len() < 10 || f[3] != "0A" {
                continue; // not in the LISTEN state
            }
            let local_port = f[1].rsplit(':').next().and_then(|p| u16::from_str_radix(p, 16).ok());
            if local_port != Some(port) {
                continue;
            }
            let uid = f[7].parse().unwrap_or(0);
            return Some(find_process(proc, f[9], uid));
        }
    }
    None
}

fn find_process(proc: &Path, inode: &str, uid: u32) -> Owner {
    let target = format!("socket:[{inode}]");
    let unseen = Owner { pid: None, uid, name: None, exe: None };
    let Ok(entries) = fs::read_dir(proc) else { return unseen };
    for entry in entries.flatten() {
        let Some(pid) = entry.file_name().to_str().and_then(|n| n.parse::<u32>().ok()) else { continue };
        let Ok(fds) = fs::read_dir(entry.path().join("fd")) else { continue };
        let holds_it = fds
            .flatten()
            .any(|fd| fs::read_link(fd.path()).is_ok_and(|l| l.to_string_lossy() == target));
        if holds_it {
            let exe = fs::read_link(entry.path().join("exe")).ok().map(|p| {
                // A replaced binary reads as "/path/agent (deleted)".
                PathBuf::from(p.to_string_lossy().trim_end_matches(" (deleted)"))
            });
            let name = fs::read_to_string(entry.path().join("comm")).ok().map(|s| s.trim().to_string());
            return Owner { pid: Some(pid), uid, name, exe };
        }
    }
    unseen
}

/// Ask the process to quit (then force it if it does not), and wait until `port` is free.
pub fn stop(owner: &Owner, port: u16) -> Result<(), String> {
    let pid = owner.pid.ok_or_else(|| {
        "It runs as another user (probably root), so it cannot be stopped from here. \
         Close it with:  sudo pkill -f desk_ctrl_agent"
            .to_string()
    })?;
    if pid == std::process::id() {
        return Err("That is this program itself.".into());
    }
    signal(pid, libc::SIGTERM, "stop")?;
    if wait_until_free(port, Duration::from_secs(3)) {
        return Ok(());
    }
    signal(pid, libc::SIGKILL, "force-stop")?;
    if wait_until_free(port, Duration::from_secs(2)) {
        Ok(())
    } else {
        Err(format!("Port {port} is still in use after stopping pid {pid}."))
    }
}

fn signal(pid: u32, sig: i32, what: &str) -> Result<(), String> {
    // SAFETY: plain kill(2) on a pid we looked up in /proc.
    if unsafe { libc::kill(pid as i32, sig) } == 0 {
        return Ok(());
    }
    let e = io::Error::last_os_error();
    Err(match e.kind() {
        io::ErrorKind::PermissionDenied => {
            format!("Not allowed to {what} pid {pid} (it runs as another user). Try:  sudo kill {pid}")
        }
        io::ErrorKind::NotFound => return Ok(()), // already gone
        _ => format!("Could not {what} pid {pid}: {e}"),
    })
}

fn wait_until_free(port: u16, timeout: Duration) -> bool {
    let end = Instant::now() + timeout;
    while Instant::now() < end {
        if listener(port).is_none() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    listener(port).is_none()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::os::unix::fs::symlink;
    use std::process::{Command, Stdio};

    fn temp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("deskctrl-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn finds_the_process_in_a_fake_proc_tree() {
        let proc = temp("proc");
        fs::create_dir_all(proc.join("net")).unwrap();
        // 0x1F49 = 8009. One non-listening row for the same port, then the real listener.
        fs::write(
            proc.join("net/tcp"),
            "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n\
             0: 0100007F:1F49 0100007F:C350 01 00000000:00000000 00:00000000 00000000  1000 0 11111 1\n\
             1: 00000000:1F49 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 22222 1\n",
        )
        .unwrap();
        fs::write(proc.join("net/tcp6"), "header\n").unwrap();
        for (pid, inode) in [(100, "99999"), (4242, "22222")] {
            let p = proc.join(pid.to_string());
            fs::create_dir_all(p.join("fd")).unwrap();
            symlink(format!("socket:[{inode}]"), p.join("fd/7")).unwrap();
            fs::write(p.join("comm"), "desk_ctrl_agent\n").unwrap();
            symlink("/usr/local/bin/desk_ctrl_agent (deleted)", p.join("exe")).unwrap();
        }

        let o = listener_in(&proc, 8009).expect("listener found");
        assert_eq!(o.pid, Some(4242), "the process that holds inode 22222");
        assert_eq!(o.uid, 1000);
        assert_eq!(o.name.as_deref(), Some("desk_ctrl_agent"));
        assert_eq!(o.exe, Some(PathBuf::from("/usr/local/bin/desk_ctrl_agent")), "'(deleted)' is stripped");
        assert!(listener_in(&proc, 8010).is_none(), "nothing listens on another port");
        fs::remove_dir_all(&proc).unwrap();
    }

    #[test]
    fn a_listener_we_cannot_see_is_reported_without_a_pid() {
        let proc = temp("proc-root");
        fs::create_dir_all(proc.join("net")).unwrap();
        fs::write(
            proc.join("net/tcp"),
            "header\n 0: 00000000:1F4A 00000000:0000 0A 00000000:00000000 00:00000000 00000000  0 0 33333 1\n",
        )
        .unwrap();
        let o = listener_in(&proc, 8010).unwrap();
        assert_eq!((o.pid, o.uid), (None, 0));
        assert!(o.describe().contains("root"));
        assert!(stop(&o, 8010).unwrap_err().contains("sudo pkill"), "tells the user what to run");
        fs::remove_dir_all(&proc).unwrap();
    }

    #[test]
    fn finds_a_real_listener_in_this_process() {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let o = listener(port).expect("our own socket is found");
        assert_eq!(o.pid, Some(std::process::id()));
        assert!(!o.is_other_agent(), "this process is not 'another' agent");
        assert!(stop(&o, port).is_err(), "never stops itself");
        drop(l);
        assert!(listener(port).is_none(), "gone once closed");
    }

    #[test]
    fn stops_another_process_and_frees_the_port() {
        // Another program listening on a port (python is just a convenient stand-in).
        let probe = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);
        let child = Command::new("python3")
            .args(["-I", "-c", "import socket,time\ns=socket.socket()\ns.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)\ns.bind(('127.0.0.1',int(__import__('sys').argv[1])))\ns.listen(1)\ntime.sleep(60)", &port.to_string()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        let Ok(mut child) = child else {
            eprintln!("python3 not available; skipping");
            return;
        };
        let end = Instant::now() + Duration::from_secs(5);
        let owner = loop {
            if let Some(o) = listener(port) {
                break o;
            }
            assert!(Instant::now() < end, "child never started listening");
            std::thread::sleep(Duration::from_millis(50));
        };
        assert_eq!(owner.pid, Some(child.id()));
        assert!(!owner.is_other_agent(), "python is not our agent");

        stop(&owner, port).expect("stopped");
        assert!(listener(port).is_none(), "port is free again");
        let _ = child.wait();
    }
}
