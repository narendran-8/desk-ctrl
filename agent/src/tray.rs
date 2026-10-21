//! Native tray lifetime and persisted window preference. Headless mode never creates a tray.
use eframe::egui;
use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder, menu::{Menu, MenuItem, MenuEvent}};

pub fn enabled() -> bool {
    crate::tokenstore::config_dir()
        .is_some_and(|d| read_at(&d.join("minimize-to-tray")))
}

fn read_at(path: &std::path::Path) -> bool {
    std::fs::read_to_string(path).is_ok_and(|s| s.trim() == "true")
}

pub fn save(enabled: bool) -> std::io::Result<()> {
    let dir = crate::tokenstore::config_dir().ok_or_else(|| std::io::Error::other("No configuration directory"))?;
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join("minimize-to-tray"), enabled.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_or_invalid_preference_keeps_the_window_visible() {
        let path = std::env::temp_dir().join(format!("deskctrl-tray-test-{}", std::process::id()));
        assert!(!read_at(&path));
        for (value, expected) in [("true", true), ("false", false), ("broken", false), ("", false)] {
            std::fs::write(&path, value).unwrap();
            assert_eq!(read_at(&path), expected);
        }
        std::fs::remove_file(path).unwrap();
    }
}

pub struct Tray {
    _icon: TrayIcon,
    quit_requested: Arc<AtomicBool>,
}

impl Tray {
    pub fn quitting(&self) -> bool {
        self.quit_requested.load(Ordering::SeqCst)
    }

    pub fn new(ctx: egui::Context) -> Result<Self, String> {
        let click_ctx = ctx.clone();
        tray_icon::TrayIconEvent::set_event_handler(Some(move |event| {
            if matches!(event, tray_icon::TrayIconEvent::DoubleClick { button: tray_icon::MouseButton::Left, .. }) {
                click_ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
                click_ctx.send_viewport_cmd(egui::ViewportCommand::Minimized(false));
                click_ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
                click_ctx.request_repaint();
            }
        }));
        let menu = Menu::new();
        let show = MenuItem::new("Show ViL", true, None);
        let quit = MenuItem::new("Close application", true, None);
        menu.append_items(&[&show, &quit]).map_err(|e| e.to_string())?;
        let show_id = show.id().clone();
        let quit_id = quit.id().clone();
        let quit_requested = Arc::new(AtomicBool::new(false));
        let quit_flag = quit_requested.clone();
        MenuEvent::set_event_handler(Some(move |event: MenuEvent| {
            if event.id == show_id {
                ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
                ctx.send_viewport_cmd(egui::ViewportCommand::Minimized(false));
                ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
            } else if event.id == quit_id {
                quit_flag.store(true, Ordering::SeqCst);
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            }
            ctx.request_repaint();
        }));
        let data = eframe::icon_data::from_png_bytes(include_bytes!("../../branding/vil-icon-256.png")).map_err(|e| e.to_string())?;
        let icon = Icon::from_rgba(data.rgba, data.width, data.height).map_err(|e| e.to_string())?;
        let icon = TrayIconBuilder::new().with_tooltip("ViL Agent")
            .with_icon(icon).with_menu(Box::new(menu)).build().map_err(|e| e.to_string())?;
        Ok(Self { _icon: icon, quit_requested })
    }
}
