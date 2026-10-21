//! "Start the agent when I log in": the standard XDG autostart entry,
//! `~/.config/autostart/deskctrl-agent.desktop`. The file itself is the setting: switched on =
//! the file exists, switched off = it is deleted. Works on GNOME, KDE, Cinnamon, XFCE ... without
//! sudo and without a systemd service.

use std::io;
use std::path::{Path, PathBuf};

pub const ENTRY_NAME: &str = "deskctrl-agent.desktop";
/// The flag that starts the window already minimised (see main.rs).
pub const MINIMIZED_FLAG: &str = "--minimized";
/// Seconds the desktop session may take to get its network, Bluetooth and adb ready first.
const DELAY_SECONDS: u32 = 5;

/// `$XDG_CONFIG_HOME/autostart/deskctrl-agent.desktop` (default `~/.config/...`).
pub fn entry_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".config")))?;
    Some(base.join("autostart").join(ENTRY_NAME))
}

/// One argument of the `Exec=` line, quoted as the Desktop Entry specification asks: in double
/// quotes when it has a space or another special character, with `"` `` ` `` `$` `\` escaped
/// and `%` doubled.
pub fn quote_exec(arg: &str) -> String {
    let special = |c: char| " \t\n\"'\\><~|&;$*?#()`".contains(c);
    let mut out = String::new();
    for c in arg.chars() {
        match c {
            '"' | '`' | '$' | '\\' => {
                out.push('\\');
                out.push(c);
            }
            '%' => out.push_str("%%"),
            c => out.push(c),
        }
    }
    if arg.is_empty() || arg.contains(special) {
        format!("\"{out}\"")
    } else {
        out
    }
}

/// The text of the autostart file for the program at `exe`.
pub fn desktop_entry(exe: &Path, minimized: bool) -> String {
    let mut exec = quote_exec(&exe.to_string_lossy());
    if minimized {
        exec.push(' ');
        exec.push_str(MINIMIZED_FLAG);
    }
    format!(
        "[Desktop Entry]\nType=Application\nName=ViL Agent\nComment=Control this computer from your phone\n\
         Exec={exec}\nTerminal=false\nX-GNOME-Autostart-enabled=true\nX-GNOME-Autostart-Delay={DELAY_SECONDS}\n"
    )
}

/// The line `Exec=...` of an autostart file, without the `Exec=`.
fn exec_line(text: &str) -> Option<&str> {
    text.lines().find_map(|l| l.strip_prefix("Exec="))
}

/// Whether the entry exists (and is not marked hidden / disabled by the desktop's own settings).
pub fn is_enabled() -> bool {
    let Some(text) = entry_path().and_then(|p| std::fs::read_to_string(p).ok()) else { return false };
    exec_line(&text).is_some()
        && !text.lines().any(|l| l.trim() == "Hidden=true" || l.trim() == "X-GNOME-Autostart-enabled=false")
}

/// Whether the entry starts the agent minimised.
pub fn is_minimized() -> bool {
    entry_path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|t| exec_line(&t).map(|l| l.split_whitespace().any(|w| w == MINIMIZED_FLAG)))
        .unwrap_or(false)
}

/// The program that is running now: what autostart should start.
pub fn current_exe() -> io::Result<PathBuf> {
    std::env::current_exe()
}

/// Switch autostart on (or change "minimised") for the program at `exe`.
pub fn enable(exe: &Path, minimized: bool) -> io::Result<()> {
    let path = entry_path().ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no home folder"))?;
    std::fs::create_dir_all(path.parent().expect("a file inside autostart/"))?;
    // Written to a temporary file first, so a login never finds half a file.
    let tmp = path.with_extension("desktop.tmp");
    std::fs::write(&tmp, desktop_entry(exe, minimized))?;
    std::fs::rename(tmp, path)
}

/// Switch autostart off. Not being on already is fine.
pub fn disable() -> io::Result<()> {
    let Some(path) = entry_path() else { return Ok(()) };
    match std::fs::remove_file(path) {
        Err(e) if e.kind() != io::ErrorKind::NotFound => Err(e),
        _ => Ok(()),
    }
}

/// At every start: if autostart is on but the program it names is gone (the agent was moved or
/// replaced), point it at this one. A program that still exists is left alone: another copy of the
/// agent (a test build, a demo run) must not take over the user's autostart. Returns whether the
/// file was rewritten.
pub fn refresh(exe: &Path) -> bool {
    if !is_enabled() {
        return false;
    }
    let minimized = is_minimized();
    let current = entry_path().and_then(|p| std::fs::read_to_string(p).ok());
    let Some(line) = current.as_deref().and_then(exec_line) else { return false };
    if program_of(line).exists() {
        return false;
    }
    enable(exe, minimized).is_ok()
}

/// The program path in an `Exec=` line: the first word, or the quoted first argument.
fn program_of(line: &str) -> PathBuf {
    let line = line.trim();
    if let Some(rest) = line.strip_prefix('"') {
        let mut out = String::new();
        let mut chars = rest.chars();
        while let Some(c) = chars.next() {
            match c {
                '\\' => out.extend(chars.next()),
                '"' => break,
                c => out.push(c),
            }
        }
        PathBuf::from(out)
    } else {
        PathBuf::from(line.split_whitespace().next().unwrap_or(""))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// The tests change XDG_CONFIG_HOME, which is shared by the whole process.
    static ENV: Mutex<()> = Mutex::new(());

    fn in_temp_config(name: &str, body: impl FnOnce(&Path)) {
        let _g = ENV.lock().unwrap_or_else(|e| e.into_inner());
        let dir = std::env::temp_dir().join(format!("deskctrl-autostart-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        // SAFETY: serialised by ENV; nothing else reads this variable while a test runs.
        unsafe { std::env::set_var("XDG_CONFIG_HOME", &dir) };
        body(&dir);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn paths_are_quoted_the_way_desktop_entries_want() {
        assert_eq!(quote_exec("/usr/local/bin/desk_ctrl_agent"), "/usr/local/bin/desk_ctrl_agent");
        assert_eq!(quote_exec("/home/me/My Apps/agent"), "\"/home/me/My Apps/agent\"");
        assert_eq!(quote_exec("/tmp/a\"b$c"), "\"/tmp/a\\\"b\\$c\"");
        assert_eq!(quote_exec("/tmp/100%"), "/tmp/100%%");
    }

    #[test]
    fn the_entry_has_what_the_desktop_needs() {
        let e = desktop_entry(Path::new("/opt/agent"), true);
        assert!(e.starts_with("[Desktop Entry]\n"));
        assert!(e.contains("\nType=Application\n"));
        assert!(e.contains("\nExec=/opt/agent --minimized\n"));
        assert!(e.contains("X-GNOME-Autostart-Delay=5"));
        assert!(!desktop_entry(Path::new("/opt/agent"), false).contains("--minimized"));
    }

    #[test]
    fn on_off_and_minimised_follow_the_file() {
        in_temp_config("onoff", |dir| {
            assert!(!is_enabled());
            enable(Path::new("/opt/agent"), true).unwrap();
            assert!(dir.join("autostart/deskctrl-agent.desktop").exists());
            assert!(is_enabled() && is_minimized());
            enable(Path::new("/opt/agent"), false).unwrap();
            assert!(is_enabled() && !is_minimized());
            disable().unwrap();
            assert!(!is_enabled());
            disable().unwrap(); // already off: no error
            assert!(!dir.join("autostart/deskctrl-agent.desktop.tmp").exists());
        });
    }

    #[test]
    fn an_entry_the_desktop_disabled_counts_as_off() {
        in_temp_config("hidden", |dir| {
            enable(Path::new("/opt/agent"), false).unwrap();
            let f = dir.join("autostart/deskctrl-agent.desktop");
            let text = std::fs::read_to_string(&f).unwrap() + "Hidden=true\n";
            std::fs::write(&f, text).unwrap();
            assert!(!is_enabled());
        });
    }

    #[test]
    fn a_moved_agent_is_pointed_at_again_but_another_working_copy_does_not_take_over() {
        in_temp_config("refresh", |dir| {
            assert!(!refresh(Path::new("/opt/new")), "off: nothing to fix");
            // The recorded program is gone: point at the one that runs now, keep "minimised".
            enable(Path::new("/opt/gone agent"), true).unwrap();
            assert!(refresh(Path::new("/opt/new")));
            let text = std::fs::read_to_string(entry_path().unwrap()).unwrap();
            assert!(text.contains("Exec=/opt/new --minimized"), "{text}");
            // The recorded program exists (here: this test's folder): a demo copy leaves it alone.
            let real = dir.join("real agent");
            std::fs::write(&real, b"x").unwrap();
            enable(&real, false).unwrap();
            assert!(!refresh(Path::new("/opt/demo copy")));
            assert!(std::fs::read_to_string(entry_path().unwrap()).unwrap().contains("real agent"));
        });
    }

    #[test]
    fn the_program_is_read_back_from_the_exec_line() {
        assert_eq!(program_of("/opt/agent --minimized"), PathBuf::from("/opt/agent"));
        assert_eq!(program_of("\"/opt/my agent\" --minimized"), PathBuf::from("/opt/my agent"));
        assert_eq!(program_of(&quote_exec("/tmp/a\"b$c")), PathBuf::from("/tmp/a\"b$c"));
    }

    #[test]
    fn an_unwritable_place_is_an_error_not_a_panic() {
        in_temp_config("readonly", |dir| {
            std::fs::write(dir.join("autostart"), b"a file where the folder should be").unwrap();
            assert!(enable(Path::new("/opt/agent"), false).is_err());
        });
    }
}
