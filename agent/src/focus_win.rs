//! "Is the focus on something you can type into?" for the phone's auto-keyboard: not built yet on
//! Windows (it would use UI Automation). The phone then simply never switches by itself.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

pub const FRAME_ID: u8 = 0x13;

pub fn spawn(stop: Arc<AtomicBool>, _on_focus: impl Fn(bool) + Send + Sync + 'static) -> JoinHandle<()> {
    thread::spawn(move || {
        while !stop.load(Ordering::Relaxed) {
            thread::sleep(Duration::from_millis(200));
        }
    })
}
