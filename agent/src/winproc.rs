//! Running helper programs on Windows without a console window flashing up.

use std::os::windows::process::CommandExt;
use std::process::Command;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// `Command::new(program)` that opens no console window (the agent itself is a window program).
pub fn quiet(program: &str) -> Command {
    let mut c = Command::new(program);
    c.creation_flags(CREATE_NO_WINDOW);
    c
}
