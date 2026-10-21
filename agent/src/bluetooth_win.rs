//! Bluetooth on Windows: not built yet. The agent says so and the phone uses Wi-Fi or USB.
//! (The Linux agent serves RFCOMM through BlueZ, see bluetooth.rs.)

use crate::server::{SharedInput, SharedState};

#[derive(Default, Clone)]
#[allow(dead_code)] // the same shape as the Linux status
pub struct BtStatus {
    pub registered: bool,
    pub adapter: Option<String>,
    pub powered: bool,
    pub channel: Option<u8>,
    pub error: Option<String>,
}

impl BtStatus {
    pub fn summary(&self) -> String {
        match &self.error {
            Some(e) => e.clone(),
            None => "Bluetooth is not available on Windows yet. Use Wi-Fi or a USB cable.".into(),
        }
    }

    pub fn ready(&self) -> bool {
        false
    }
}

pub struct BtService;

impl BtService {
    pub fn start(shared: SharedState, _input: SharedInput) -> Self {
        shared.lock().unwrap().bt = BtStatus {
            error: Some("Bluetooth is not available on Windows yet. Use Wi-Fi or a USB cable.".into()),
            ..Default::default()
        };
        Self
    }

    /// Nobody is connected over Bluetooth, so there is nobody to send to.
    pub fn broadcaster(&self) -> impl Fn(&[u8]) + Send + 'static {
        |_payload: &[u8]| {}
    }

    pub fn stop(&mut self) {}
}
