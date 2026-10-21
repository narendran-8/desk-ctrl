use crate::portowner::{self, Owner};
use crate::server::{local_ip, make_token, Server, Transport};
use crate::look::{bold, running_badge, status_pill, transport_icon, Pill, AMBER, BG, DIM, GREEN, LINE, TEAL, TEXT};
use eframe::egui::{self, Align, Color32, Layout, RichText, Stroke};
use std::time::Duration;

pub struct App {
    server: Server,
    port: u16,
    ip: Option<String>,
    usb_msg: String,
    /// Result of the last "stop the other copy" attempt.
    action_msg: String,
    tab: Tab,
    show_settings: bool,
    /// Started with --minimized: use the tray when enabled, otherwise the taskbar.
    pub start_minimized: bool,
    autostart_msg: String,
    tray: Option<crate::tray::Tray>,
    minimize_to_tray: bool,
    tray_error: String,
}

impl App {
    pub fn new(mut server: Server, port: u16) -> Self {
        server.start(port);
        // DESK_SHOW=settings | log opens that view at once (for screenshots of the window).
        let show = std::env::var("DESK_SHOW").unwrap_or_default();
        Self { server, port, ip: local_ip(), usb_msg: String::new(), action_msg: String::new(), tab: if show == "log" { Tab::Log } else { Tab::Connect }, show_settings: show == "settings", start_minimized: false, autostart_msg: String::new(), tray: None, minimize_to_tray: crate::tray::enabled(), tray_error: String::new() }
    }

    /// The port is taken: say by whom and offer the way out.
    fn port_help(&mut self, ui: &mut egui::Ui, owner: &Owner) {
        if owner.is_other_agent() {
            ui.label(RichText::new("It is another copy of this agent, so it can be stopped from here.").size(14.0));
            if ui.button("Stop it and start here").clicked() {
                match portowner::stop(owner, self.port) {
                    Ok(()) => {
                        self.action_msg.clear();
                        self.server.shared.lock().unwrap().log("Stopped the other agent");
                        self.server.start(self.port);
                    }
                    Err(e) => self.action_msg = e,
                }
            }
        } else if owner.pid.is_none() {
            ui.label(RichText::new("It was probably started with sudo, so close it from a terminal, then press Start:").size(14.0));
            let cmd = "sudo pkill -f desk_ctrl_agent";
            ui.horizontal(|ui| {
                ui.monospace(cmd);
                if ui.small_button("Copy").clicked() {
                    ui.ctx().copy_text(cmd.to_string());
                }
            });
        } else {
            ui.label(RichText::new(format!(
                "Close that program, or run the agent on another port (for example DESK_PORT={}).",
                self.port.saturating_add(1)
            )).size(14.0));
        }
        if !self.action_msg.is_empty() {
            ui.add(egui::Label::new(RichText::new(&self.action_msg).size(14.0).color(Color32::LIGHT_RED)).wrap());
        }
    }

    fn enable_usb(&mut self) {
        let p = self.port.to_string();
        self.usb_msg = match std::process::Command::new("adb")
            .args(["reverse", &format!("tcp:{p}"), &format!("tcp:{p}")])
            .output()
        {
            Ok(o) if o.status.success() => "USB tunnel ready - use host 127.0.0.1 in the app".into(),
            Ok(o) => format!("adb failed: {}", String::from_utf8_lossy(&o.stderr).trim()),
            Err(e) => format!("adb not found: {e}"),
        };
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Tab {
    Connect,
    Log,
}

/// The address without its port: "172.22.36.159:44974" -> "172.22.36.159".
fn host_of(addr: &str) -> &str {
    match addr.rsplit_once(':') {
        Some((h, p)) if p.chars().all(|c| c.is_ascii_digit()) => h.trim_start_matches('[').trim_end_matches(']'),
        _ => addr,
    }
}

/// How a connected phone is told apart: the way it is connected.
fn client_tag(c: &crate::server::Client) -> &'static str {
    // A phone on the cable reaches the agent through adb's tunnel, so it comes from localhost.
    let cable = c.transport == Transport::WiFi && crate::identity::is_loopback(&c.addr);
    match c.transport {
        _ if cable => "USB",
        Transport::WiFi => "Wi-Fi",
        Transport::Bluetooth => "Bluetooth",
    }
}

/// A label that copies its text when clicked.
fn copyable(ui: &mut egui::Ui, text: &str, size: f32) {
    let r = ui.add(egui::Label::new(RichText::new(text).size(size).color(TEXT)).sense(egui::Sense::click()));
    if r.on_hover_text("Click to copy").clicked() {
        ui.ctx().copy_text(text.to_string());
    }
}

fn dim(text: &str, size: f32) -> RichText {
    RichText::new(text).size(size).color(DIM)
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        ctx.request_repaint_after(Duration::from_millis(500));
        if self.minimize_to_tray && self.tray.is_none() && self.tray_error.is_empty() {
            match crate::tray::Tray::new(ctx.clone()) {
                Ok(tray) => self.tray = Some(tray),
                Err(e) => self.tray_error = format!("Tray unavailable: {e}"),
            }
        }
        if self.start_minimized {
            self.start_minimized = false;
            ctx.send_viewport_cmd(egui::ViewportCommand::Minimized(true));
        }
        if ctx.input(|i| i.viewport().close_requested())
            && self.minimize_to_tray
            && self.tray.as_ref().is_some_and(|tray| !tray.quitting())
        {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
        }
        if self.minimize_to_tray && self.tray.is_some() && ctx.input(|i| i.viewport().minimized == Some(true)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
        }

        let (running, error, token, clients, log, bt, owner, usb) = {
            let s = self.server.shared.lock().unwrap();
            (
                s.running,
                s.error.clone(),
                s.token.clone(),
                s.clients.clone(),
                s.log.clone(),
                s.bt.clone(),
                s.port_owner.clone(),
                s.usb.clone(),
            )
        };

        egui::CentralPanel::default().frame(egui::Frame::new().fill(BG).inner_margin(egui::Margin::symmetric(24, 16))).show(ui, |ui| {
            ui.spacing_mut().item_spacing = egui::vec2(10.0, 6.0);

            // Header: the name on the left; the run state and Settings on the right.
            ui.horizontal(|ui| {
                ui.label(RichText::new("ViL Agent").size(25.0).color(Color32::from_rgb(238, 238, 238)));
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    let settings = ui.add(egui::Button::new(RichText::new("\u{2699}  Settings").size(16.0).color(TEXT)).frame(false));
                    if settings.clicked() {
                        self.show_settings = !self.show_settings;
                    }
                    ui.add_space(6.0);
                    running_badge(ui, if running { "Running" } else { "Stopped" }, running);
                    if !running && ui.add(egui::Button::new(RichText::new("Start").size(15.0)).min_size(egui::vec2(64.0, 30.0))).clicked() {
                        self.action_msg.clear();
                        self.server.start(self.port);
                    }
                });
            });
            // A problem and what to do about it: one tinted block, not loose lines.
            let help_owner = if running { None } else { owner.clone() };
            if error.is_some() || help_owner.is_some() {
                egui::Frame::new()
                    .fill(Color32::from_rgb(50, 34, 34))
                    .corner_radius(8.0)
                    .inner_margin(egui::Margin::symmetric(12, 8))
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        if let Some(e) = &error {
                            ui.add(egui::Label::new(RichText::new(e).size(14.0).color(Color32::LIGHT_RED)).wrap());
                        }
                        if let Some(o) = &help_owner {
                            self.port_help(ui, o);
                        }
                    });
                ui.add_space(4.0);
            }

            ui.add_space(2.0);
            self.tabs(ui);

            match self.tab {
                Tab::Connect => self.connect_tab(ui, &token, &bt, &usb, &clients),
                Tab::Log => self.log_tab(ui, &log),
            }
        });

        let mut open = self.show_settings;
        // As tall as the window allows, and scrolls when the settings are longer than that.
        let max_h = (ctx.content_rect().height() - 64.0).max(180.0);
        egui::Window::new("Settings")
            .open(&mut open)
            .collapsible(false)
            .resizable(false)
            .vscroll(true)
            .max_height(max_h)
            .default_width(300.0)
            .anchor(egui::Align2::RIGHT_TOP, [-14.0, 52.0])
            .show(&ctx, |ui| {
                ui.set_width(300.0);
                self.settings_ui(ui, running, &bt, &usb)
            });
        self.show_settings = open;
    }
}

impl App {
    /// "Connect" and "Log": plain words, the open one in teal with a line under it that sits on a
    /// thin divider running the full width.
    fn tabs(&mut self, ui: &mut egui::Ui) {
        let mut selected = None;
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = 32.0;
            for (name, tab) in [("Connect", Tab::Connect), ("Log", Tab::Log)] {
                let on = self.tab == tab;
                let color = if on { TEAL } else { Color32::from_rgb(196, 196, 196) };
                let r = ui.add(egui::Label::new(RichText::new(name).size(18.0).color(color)).sense(egui::Sense::click()));
                if r.clicked() {
                    self.tab = tab;
                }
                if on {
                    selected = Some(r.rect);
                }
            }
        });
        if let Some(r) = selected {
            let y = r.bottom() + 6.0;
            let full = ui.max_rect();
            ui.painter().hline(full.x_range(), y, Stroke::new(1.0, LINE));
            ui.painter().hline(r.x_range(), y, Stroke::new(2.5, TEAL));
        }
        ui.add_space(14.0);
    }

    /// The pairing details and what is connected: the QR code on the left, a thin line, and on the
    /// right the address, port and token, the Bluetooth and USB state, and the connected devices.
    ///
    /// Everything sits on one grid: the three detail rows and the two status rows share their
    /// baselines (26 px rows), the pills are one width, and the device table's header, its rows and
    /// its empty message start at the same x.
    fn connect_tab(
        &mut self,
        ui: &mut egui::Ui,
        token: &str,
        bt: &crate::bluetooth::BtStatus,
        usb: &crate::usb::UsbStatus,
        clients: &[crate::server::Client],
    ) {
        const ROW_H: f32 = 26.0;
        const GAP: f32 = 18.0; // either side of the thin line between the two halves
        let area = ui.available_rect_before_wrap();
        let left_w = (area.width() * 0.30).clamp(170.0, 200.0);
        let left = egui::Rect::from_min_size(area.min, egui::vec2(left_w, area.height()));
        let right = egui::Rect::from_min_max(egui::pos2(left.right() + 2.0 * GAP + 1.0, area.top()), area.max);
        ui.painter().vline(left.right() + GAP, (area.top() + 2.0)..=(area.bottom() - 8.0), Stroke::new(1.0, LINE));

        // Left: the QR code and its caption, centred in their half.
        ui.scope_builder(egui::UiBuilder::new().max_rect(left).layout(Layout::top_down(Align::Center)), |ui| {
            ui.add_space(4.0);
            if let Some(qr) = pair_uri(self.ip.as_deref(), self.port, token, bt.adapter.as_deref()) {
                draw_qr(ui, &qr, left_w - 20.0);
                ui.add_space(10.0);
                ui.label(RichText::new("Scan with the phone app").size(14.0).color(TEAL));
            } else {
                ui.add_space(30.0);
                ui.label(dim("No network or Bluetooth to pair with", 14.0));
            }
        });

        // Right: details and status on one grid, then the devices.
        ui.scope_builder(egui::UiBuilder::new().max_rect(right).layout(Layout::top_down(Align::Min)), |ui| {
            ui.add_space(2.0);
            let auto = self.server.usb_auto.load(std::sync::atomic::Ordering::Relaxed);
            let (bt_text, bt_kind) = if bt.adapter.is_none() {
                ("N/A", Pill::Warn)
            } else if bt.ready() {
                ("Ready", Pill::Good)
            } else {
                ("Problem", Pill::Warn)
            };
            let (usb_text, usb_kind, usb_hint) = if !auto {
                ("Off", Pill::Idle, "Automatic USB connecting is off (Settings)".to_string())
            } else if !usb.phones.is_empty() {
                ("Connected", Pill::Good, format!("{} plugged in (serial {})", usb.phones[0].model, usb.phones[0].serial))
            } else if let Some(h) = &usb.hint {
                ("Needs setup", Pill::Warn, h.clone())
            } else {
                ("Waiting", Pill::Idle, "Plug in a phone with USB debugging on".to_string())
            };
            let cell = |ui: &mut egui::Ui, w: f32, add: &mut dyn FnMut(&mut egui::Ui)| {
                ui.allocate_ui_with_layout(egui::vec2(w, ROW_H), Layout::left_to_right(Align::Center), |ui| {
                    ui.set_min_size(egui::vec2(w, ROW_H));
                    add(ui);
                });
            };
            let details = [("Wi-Fi", self.ip.clone().unwrap_or_else(|| "unknown".into())), ("Port", self.port.to_string()), ("Token", token.to_string())];
            let mut divider: Option<(f32, f32, f32)> = None; // x, top, bottom
            egui::Grid::new("conn").num_columns(5).spacing([10.0, 8.0]).show(ui, |ui| {
                for (row, (label, value)) in details.iter().enumerate() {
                    cell(ui, 46.0, &mut |ui| {
                        ui.label(dim(label, 15.0));
                    });
                    cell(ui, 150.0, &mut |ui| copyable(ui, value, 15.5));
                    // A narrow column that only carries the thin line between details and status.
                    let (r, _) = ui.allocate_exact_size(egui::vec2(GAP * 1.3, ROW_H), egui::Sense::hover());
                    match (&mut divider, row) {
                        (d, 0) => *d = Some((r.center().x, r.top(), r.bottom())),
                        (Some(d), _) => d.2 = r.bottom(),
                        _ => {}
                    }
                    match row {
                        0 => {
                            cell(ui, 72.0, &mut |ui| {
                                ui.label(dim("Bluetooth:", 15.0));
                            });
                            cell(ui, 84.0, &mut |ui| {
                                status_pill(ui, bt_text, bt_kind).on_hover_text(bt.summary());
                            });
                        }
                        1 => {
                            cell(ui, 72.0, &mut |ui| {
                                ui.label(dim("USB:", 15.0));
                            });
                            cell(ui, 84.0, &mut |ui| {
                                status_pill(ui, usb_text, usb_kind).on_hover_text(usb_hint.clone());
                            });
                        }
                        _ => {
                            cell(ui, 72.0, &mut |_| {});
                            cell(ui, 84.0, &mut |_| {});
                        }
                    }
                    ui.end_row();
                }
            });
            if let Some((x, top, bottom)) = divider {
                ui.painter().vline(x, top..=bottom, Stroke::new(1.0, LINE));
            }

            ui.add_space(12.0);
            let y = ui.cursor().top();
            ui.painter().hline(right.left()..=right.right(), y, Stroke::new(1.0, LINE));
            ui.add_space(12.0);
            ui.label(bold("Connected Devices", 16.0));
            ui.add_space(6.0);
            self.devices_table(ui, right.width(), usb, clients);
        });
    }

    /// Name and address of every phone that is connected, one thin-lined row each. The header, the
    /// rows and the empty message share the same columns: icon, name, address.
    fn devices_table(&self, ui: &mut egui::Ui, width: f32, usb: &crate::usb::UsbStatus, clients: &[crate::server::Client]) {
        const ROW_H: f32 = 28.0;
        let icon_w = 34.0;
        let name_w = (width * 0.52).max(150.0);
        let row = |ui: &mut egui::Ui, icon: Option<&str>, name: RichText, value: RichText| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 0.0;
                ui.allocate_ui_with_layout(egui::vec2(icon_w, ROW_H), Layout::left_to_right(Align::Center), |ui| {
                    ui.set_min_size(egui::vec2(icon_w, ROW_H)); // a fixed column, however little is in it
                    if let Some(tag) = icon {
                        transport_icon(ui, tag, Color32::from_rgb(104, 172, 160));
                    }
                });
                ui.allocate_ui_with_layout(egui::vec2(name_w - icon_w, ROW_H), Layout::left_to_right(Align::Center), |ui| {
                    ui.set_min_size(egui::vec2(name_w - icon_w, ROW_H));
                    ui.label(name);
                });
                ui.allocate_ui_with_layout(egui::vec2(width - name_w, ROW_H), Layout::left_to_right(Align::Center), |ui| {
                    ui.set_min_size(egui::vec2(width - name_w, ROW_H));
                    ui.label(value);
                });
            });
        };
        let line = |ui: &mut egui::Ui| {
            let y = ui.cursor().top();
            let x = ui.cursor().left();
            ui.painter().hline(x..=(x + width), y, Stroke::new(1.0, LINE));
        };
        ui.spacing_mut().item_spacing.y = 0.0;
        row(ui, None, dim("Name", 13.0), dim("IP", 13.0));
        line(ui);
        if clients.is_empty() {
            // Under the "Name" column, in the same row height as a device would take.
            ui.horizontal(|ui| {
                ui.add_space(icon_w);
                ui.allocate_ui_with_layout(egui::vec2(width - icon_w, ROW_H), Layout::left_to_right(Align::Center), |ui| {
                    ui.label(dim("No phone connected yet", 15.0));
                });
            });
            return;
        }
        for (n, c) in clients.iter().enumerate() {
            let tag = client_tag(c);
            let (name, value) = match tag {
                "USB" => ("USB device".to_string(), usb.phones.first().map(|p| p.model.clone()).unwrap_or_else(|| "cable".into())),
                "Bluetooth" => ("Phone".to_string(), c.addr.clone()),
                _ => (format!("Phone {}", n + 1), host_of(&c.addr).to_string()),
            };
            row(ui, Some(tag), RichText::new(name).size(16.0).color(TEXT), RichText::new(value).size(16.0).color(TEXT));
            line(ui);
        }
    }

    /// What used to be buttons in the window: run state, a new token, USB tools.
    fn settings_ui(&mut self, ui: &mut egui::Ui, running: bool, bt: &crate::bluetooth::BtStatus, usb: &crate::usb::UsbStatus) {
        ui.spacing_mut().item_spacing = egui::vec2(8.0, 7.0);
        ui.label(bold("Agent", 14.0).color(TEAL));
        ui.horizontal(|ui| {
            if running {
                if ui
                    .button("Reconnect")
                    .on_hover_text("Restart the agent. Connected phones are dropped and reconnect on their own.")
                    .clicked()
                {
                    self.server.restart(self.port);
                }
                if ui.button("Stop").clicked() {
                    self.server.stop();
                }
            } else if ui.button("Start").clicked() {
                self.action_msg.clear();
                self.server.start(self.port);
            }
        });
        ui.separator();
        ui.label(bold("Start-up", 14.0).color(TEAL));
        self.startup_ui(ui);
        ui.separator();
        ui.label(bold("Window", 14.0).color(TEAL));
        if ui.checkbox(&mut self.minimize_to_tray, "Minimize to tray").changed() {
            self.tray_error.clear();
            if let Err(e) = crate::tray::save(self.minimize_to_tray) {
                self.tray_error = format!("Could not save tray setting: {e}");
            }
            if !self.minimize_to_tray {
                self.tray = None;
            }
        }
        ui.label(dim("Closing or minimizing the window keeps the agent in the tray. Right-click the tray icon to open or close the application.", 12.0));
        if ui.add_enabled(self.tray.is_some(), egui::Button::new("Minimize to tray now")).clicked() {
            ui.ctx().send_viewport_cmd(egui::ViewportCommand::Minimized(true));
        }
        if !self.tray_error.is_empty() {
            ui.label(RichText::new(&self.tray_error).color(AMBER));
        }
        ui.separator();
        ui.label(bold("Pairing", 14.0).color(TEAL));
        if ui.button("New token").on_hover_text("The token is remembered across restarts. A new one is only needed if a phone was lost; phones paired with the old token must pair again").clicked() {
            let token = make_token();
            crate::tokenstore::save(&token);
            self.server.shared.lock().unwrap().token = token;
        }
        ui.separator();
        ui.label(bold("USB", 14.0).color(TEAL));
        let mut auto = self.server.usb_auto.load(std::sync::atomic::Ordering::Relaxed);
        if ui.checkbox(&mut auto, "Connect phones plugged in by USB automatically").changed() {
            self.server.usb_auto.store(auto, std::sync::atomic::Ordering::Relaxed);
        }
        if let Some(h) = &usb.hint {
            ui.add(egui::Label::new(RichText::new(h).color(AMBER)).wrap());
        }
        if ui.button("Set up the USB tunnel now").on_hover_text("adb reverse: connect over a USB cable, host 127.0.0.1").clicked() {
            self.enable_usb();
        }
        if !self.usb_msg.is_empty() {
            ui.add(egui::Label::new(RichText::new(&self.usb_msg).small().weak()).wrap());
        }
        ui.separator();
        ui.label(bold("Bluetooth", 14.0).color(TEAL));
        let color = if bt.ready() { GREEN } else { AMBER };
        ui.add(egui::Label::new(RichText::new(bt.summary()).color(color)).wrap());
    }

    /// "Start the agent when I log in" and "start minimised": the autostart file is the setting.
    fn startup_ui(&mut self, ui: &mut egui::Ui) {
        let mut on = crate::autostart::is_enabled();
        let minimized = if on { crate::autostart::is_minimized() } else { true };
        let mut changed = false;
        if ui.checkbox(&mut on, "Start the agent when I log in").changed() {
            self.autostart_msg.clear();
            let result = if on {
                crate::autostart::current_exe().and_then(|exe| crate::autostart::enable(&exe, minimized))
            } else {
                crate::autostart::disable()
            };
            if let Err(e) = result {
                self.autostart_msg = format!("Could not change it: {e}");
            }
            changed = true;
        }
        // Shown ticked only while autostart is on; switching autostart on starts minimised.
        let mut shown = on && minimized;
        ui.add_enabled_ui(crate::autostart::is_enabled(), |ui| {
            if ui
                .checkbox(&mut shown, "Start minimised")
                .on_hover_text("The window opens on the taskbar instead of in front of your work")
                .changed()
            {
                self.autostart_msg.clear();
                if let Err(e) = crate::autostart::current_exe().and_then(|exe| crate::autostart::enable(&exe, shown)) {
                    self.autostart_msg = format!("Could not change it: {e}");
                }
            }
        });
        if !self.autostart_msg.is_empty() {
            ui.add(egui::Label::new(RichText::new(&self.autostart_msg).color(AMBER)).wrap());
        } else if changed && on {
            ui.add(egui::Label::new(RichText::new("It starts the next time you log in.").small().weak()).wrap());
        }
    }

    fn log_tab(&mut self, ui: &mut egui::Ui, log: &[String]) {
        ui.horizontal(|ui| {
            ui.label(dim(&format!("{} lines", log.len()), 14.0));
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                if ui.button("Clear").clicked() {
                    self.server.shared.lock().unwrap().log.clear();
                }
                if ui.button("Copy all").clicked() {
                    ui.ctx().copy_text(log.join("\n"));
                }
            });
        });
        ui.add_space(4.0);
        egui::Frame::new()
            .fill(Color32::from_rgb(28, 28, 28))
            .corner_radius(8.0)
            .inner_margin(egui::Margin::same(8))
            .show(ui, |ui| {
                ui.set_width(ui.available_width());
                egui::ScrollArea::vertical().stick_to_bottom(true).auto_shrink([false, false]).show(ui, |ui| {
                    if log.is_empty() {
                        ui.label(dim("Nothing yet", 14.0));
                    }
                    for line in log {
                        ui.monospace(line);
                    }
                });
            });
    }
}

/// `deskctrl://pair/<token>?ip=..&port=..&bt=..` - every part but the token is optional.
fn pair_uri(ip: Option<&str>, port: u16, token: &str, bt: Option<&str>) -> Option<String> {
    if ip.is_none() && bt.is_none() {
        return None;
    }
    let mut q = vec![format!("port={port}"), format!("id={}", crate::identity::computer_id())];
    if let Some(ip) = ip {
        q.push(format!("ip={ip}"));
    }
    if let Some(bt) = bt {
        q.push(format!("bt={bt}"));
    }
    Some(format!("deskctrl://pair/{token}?{}", q.join("&")))
}

/// Render a QR code as black/white squares with a white quiet-zone border.
fn draw_qr(ui: &mut egui::Ui, data: &str, max_side: f32) {
    let Ok(code) = qrcode::QrCode::new(data.as_bytes()) else { return };
    let n = code.width();
    let colors = code.to_colors();
    let quiet = 2.0;
    // As big as fits, in whole pixels so the squares stay sharp.
    let cell = (max_side / (n as f32 + quiet * 2.0)).floor().clamp(3.0, 6.0);
    let side = (n as f32 + quiet * 2.0) * cell;
    let (rect, _) = ui.allocate_exact_size(egui::vec2(side, side), egui::Sense::hover());
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 0.0, Color32::WHITE);
    for y in 0..n {
        for x in 0..n {
            if colors[y * n + x] == qrcode::Color::Dark {
                let min = rect.min + egui::vec2((x as f32 + quiet) * cell, (y as f32 + quiet) * cell);
                painter.rect_filled(egui::Rect::from_min_size(min, egui::vec2(cell, cell)), 0.0, Color32::BLACK);
            }
        }
    }
}
