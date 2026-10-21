//! The pairing token is kept across restarts, so phones that were paired once stay paired:
//! `~/.config/deskctrl/token` (or `$XDG_CONFIG_HOME/deskctrl/token`), readable by you only.
//! "New token" in the window replaces it on purpose; `DESK_TOKEN` (tests, demos) overrides it.

use std::io::Write;
use std::path::{Path, PathBuf};

/// `~/.config/deskctrl` (or under `$XDG_CONFIG_HOME`); on Windows `%APPDATA%\\deskctrl`.
pub fn config_dir() -> Option<PathBuf> {
    #[cfg(unix)]
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".config")))?;
    #[cfg(windows)]
    let base = std::env::var_os("APPDATA").filter(|p| !p.is_empty()).map(PathBuf::from)?;
    Some(base.join("deskctrl"))
}

pub fn token_path() -> Option<PathBuf> {
    config_dir().map(|d| d.join("token"))
}

/// Letters and digits only, a sensible length: anything else in the file is not our token.
fn valid(token: &str) -> bool {
    (8..=128).contains(&token.len()) && token.chars().all(|c| c.is_ascii_alphanumeric())
}

pub fn save_at(path: &Path, token: &str) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        let mut b = std::fs::DirBuilder::new();
        b.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            b.mode(0o700);
        }
        b.create(dir)?;
    }
    // Written to a temporary file first, so a crash never leaves half a token.
    let tmp = path.with_extension("tmp");
    let _ = std::fs::remove_file(&tmp);
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600); // only you can read it
    }
    let mut f = opts.open(&tmp)?;
    f.write_all(token.as_bytes())?;
    f.write_all(b"\n")?;
    f.sync_all()?;
    std::fs::rename(tmp, path)
}

/// The saved token, or a new one that is saved now. If the file cannot be written the new token
/// is still returned (it then lasts until the agent stops, as before).
pub fn load_or_create_at(path: &Path, fresh: impl FnOnce() -> String) -> String {
    if let Ok(text) = std::fs::read_to_string(path) {
        let t = text.trim();
        if valid(t) {
            return t.to_string();
        }
    }
    let token = fresh();
    if let Err(e) = save_at(path, &token) {
        eprintln!("could not save the pairing token in {}: {e}", path.display());
    }
    token
}

pub fn load_or_create(fresh: impl FnOnce() -> String) -> String {
    match token_path() {
        Some(p) => load_or_create_at(&p, fresh),
        None => fresh(),
    }
}

/// Remember `token` (after "New token"). Errors are only reported: the running agent keeps it.
pub fn save(token: &str) {
    if let Some(p) = token_path() {
        if let Err(e) = save_at(&p, token) {
            eprintln!("could not save the pairing token in {}: {e}", p.display());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("deskctrl-token-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn the_first_start_makes_a_token_and_every_later_start_has_the_same_one() {
        let d = dir("same");
        let path = d.join("deskctrl/token");
        let first = load_or_create_at(&path, || "aaaa1111bbbb2222".into());
        assert_eq!(first, "aaaa1111bbbb2222");
        let second = load_or_create_at(&path, || panic!("must not make another"));
        assert_eq!(second, first);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[cfg(unix)]
    #[test]
    fn the_file_is_private() {
        let d = dir("private");
        let path = d.join("deskctrl/token");
        load_or_create_at(&path, || "aaaa1111bbbb2222".into());
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(std::fs::metadata(path.parent().unwrap()).unwrap().permissions().mode() & 0o777, 0o700);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_new_token_replaces_the_saved_one() {
        let d = dir("new");
        let path = d.join("deskctrl/token");
        load_or_create_at(&path, || "aaaa1111bbbb2222".into());
        save_at(&path, "cccc3333dddd4444").unwrap();
        assert_eq!(load_or_create_at(&path, || panic!("kept")), "cccc3333dddd4444");
        assert!(!path.with_extension("tmp").exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn rubbish_in_the_file_is_replaced() {
        let d = dir("rubbish");
        let path = d.join("deskctrl/token");
        for bad in ["", "short", "has spaces in it 12345", "<html>not a token</html>"] {
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, bad).unwrap();
            assert_eq!(load_or_create_at(&path, || "eeee5555ffff6666".into()), "eeee5555ffff6666", "{bad:?}");
        }
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn an_unwritable_place_still_gives_a_working_token() {
        let d = dir("unwritable");
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("deskctrl"), b"a file where the folder should be").unwrap();
        let t = load_or_create_at(&d.join("deskctrl/token"), || "gggg7777hhhh8888".into());
        assert_eq!(t, "gggg7777hhhh8888");
        let _ = std::fs::remove_dir_all(&d);
    }
}
