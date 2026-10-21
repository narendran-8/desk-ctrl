//! How the agent window looks: colours, fonts and the little icons.
//!
//! Dark charcoal window, muted teal accents, thin grey dividers, and a clean sans-serif font
//! (Noto Sans when this computer has it; otherwise egui's own).

use eframe::egui::{
    self, epaint::PathShape, Color32, FontData, FontDefinitions, FontFamily, Pos2, Rect, RichText, Stroke, Vec2,
};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

pub const BG: Color32 = Color32::from_rgb(35, 35, 35);
pub const LINE: Color32 = Color32::from_rgb(68, 68, 68);
pub const TEXT: Color32 = Color32::from_rgb(228, 228, 228);
pub const DIM: Color32 = Color32::from_rgb(128, 128, 128);
pub const TEAL: Color32 = Color32::from_rgb(120, 182, 170);
pub const AMBER: Color32 = Color32::from_rgb(205, 172, 108);
pub const RED: Color32 = Color32::from_rgb(226, 110, 110);
pub const GREEN: Color32 = Color32::from_rgb(126, 190, 164);

static BOLD_FONT: AtomicBool = AtomicBool::new(false);

fn font_file(name: &str) -> Option<Vec<u8>> {
    for dir in ["/usr/share/fonts/truetype/noto", "/usr/share/fonts/noto", "/usr/share/fonts/TTF", "/usr/share/fonts/google-noto"] {
        if let Ok(bytes) = std::fs::read(format!("{dir}/{name}")) {
            return Some(bytes);
        }
    }
    None
}

/// Colours and fonts for the whole window.
pub fn install(ctx: &egui::Context) {
    let mut fonts = FontDefinitions::default();
    if let Some(regular) = font_file("NotoSans-Regular.ttf") {
        fonts.font_data.insert("noto".into(), Arc::new(FontData::from_owned(regular)));
        fonts.families.get_mut(&FontFamily::Proportional).unwrap().insert(0, "noto".into());
        if let Some(bold) = font_file("NotoSans-Bold.ttf") {
            fonts.font_data.insert("noto-bold".into(), Arc::new(FontData::from_owned(bold)));
            let mut chain = vec!["noto-bold".to_string()];
            chain.extend(fonts.families[&FontFamily::Proportional].iter().cloned());
            fonts.families.insert(FontFamily::Name("bold".into()), chain);
            BOLD_FONT.store(true, Ordering::Relaxed);
        }
    }
    ctx.set_fonts(fonts);

    let mut v = egui::Visuals::dark();
    v.panel_fill = BG;
    v.window_fill = Color32::from_rgb(42, 42, 42);
    v.window_stroke = Stroke::new(1.0, LINE);
    v.extreme_bg_color = Color32::from_rgb(28, 28, 28);
    v.faint_bg_color = Color32::from_rgb(40, 40, 40);
    v.widgets.noninteractive.bg_stroke = Stroke::new(1.0, LINE);
    v.widgets.noninteractive.fg_stroke = Stroke::new(1.0, TEXT);
    v.widgets.inactive.weak_bg_fill = Color32::from_rgb(52, 52, 52);
    v.widgets.inactive.bg_fill = Color32::from_rgb(52, 52, 52);
    v.widgets.hovered.weak_bg_fill = Color32::from_rgb(62, 62, 62);
    v.selection.bg_fill = Color32::from_rgb(52, 88, 82);
    ctx.set_visuals(v);
}

/// Bold text (the bold font when it exists, otherwise just a brighter colour).
pub fn bold(text: impl Into<String>, size: f32) -> RichText {
    let t = RichText::new(text).size(size).color(Color32::from_rgb(238, 238, 238));
    if BOLD_FONT.load(Ordering::Relaxed) {
        t.family(FontFamily::Name("bold".into()))
    } else {
        t.strong()
    }
}

/// A rounded badge: dark fill, thin outline in the same hue, coloured text.
pub fn badge(ui: &mut egui::Ui, text: &str, text_color: Color32, fill: Color32, outline: Color32, size: f32) -> egui::Response {
    egui::Frame::new()
        .fill(fill)
        .stroke(Stroke::new(1.0, outline))
        .corner_radius(14.0)
        .inner_margin(egui::Margin::symmetric(14, 3))
        .show(ui, |ui| {
            ui.label(RichText::new(text).size(size).color(text_color));
        })
        .response
}

/// The "Running" badge: dark teal fill, soft outline.
pub fn running_badge(ui: &mut egui::Ui, text: &str, ok: bool) -> egui::Response {
    if ok {
        badge(ui, text, Color32::from_rgb(132, 196, 178), Color32::from_rgb(26, 40, 39), Color32::from_rgb(74, 104, 100), 15.0)
    } else {
        badge(ui, text, RED, Color32::from_rgb(52, 30, 30), Color32::from_rgb(120, 70, 70), 15.0)
    }
}

/// A status pill ("N/A", "Connected"): amber for something missing, green for working, grey otherwise.
/// All pills are the same width, so a column of them lines up whatever the words are.
pub fn status_pill(ui: &mut egui::Ui, text: &str, kind: Pill) -> egui::Response {
    const WIDTH: f32 = 84.0;
    let (fill, fg) = match kind {
        Pill::Warn => (Color32::from_rgb(90, 74, 46), Color32::from_rgb(214, 182, 118)),
        Pill::Good => (Color32::from_rgb(46, 80, 72), Color32::from_rgb(138, 196, 176)),
        Pill::Idle => (Color32::from_rgb(56, 56, 56), Color32::from_rgb(160, 160, 160)),
    };
    egui::Frame::new()
        .fill(fill)
        .corner_radius(13.0)
        .inner_margin(egui::Margin::symmetric(0, 2))
        .show(ui, |ui| {
            ui.set_width(WIDTH);
            ui.vertical_centered(|ui| {
                ui.label(RichText::new(text).size(14.0).color(fg));
            });
        })
        .response
}

#[derive(Clone, Copy)]
pub enum Pill {
    Warn,
    Good,
    Idle,
}

fn arc(center: Pos2, radius: f32, from_deg: f32, to_deg: f32) -> Vec<Pos2> {
    (0..=10)
        .map(|i| {
            let a = (from_deg + (to_deg - from_deg) * i as f32 / 10.0).to_radians();
            center + Vec2::new(a.cos(), a.sin()) * radius
        })
        .collect()
}

/// Small line icons for the transports, 22 px wide.
pub fn transport_icon(ui: &mut egui::Ui, tag: &str, color: Color32) {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(24.0, 22.0), egui::Sense::hover());
    let p = ui.painter_at(rect);
    let c = rect.center();
    let s = Stroke::new(1.6, color);
    match tag {
        "USB" => {
            // A trident: a stem with a ring at the foot, one branch ending in a ring, one in a square.
            p.line_segment([Pos2::new(c.x, c.y - 8.0), Pos2::new(c.x, c.y + 5.0)], s);
            p.circle_stroke(Pos2::new(c.x, c.y + 7.5), 2.4, s);
            p.add(PathShape::line(vec![Pos2::new(c.x, c.y + 1.0), Pos2::new(c.x - 5.0, c.y - 2.5), Pos2::new(c.x - 5.0, c.y - 4.0)], s));
            p.circle_stroke(Pos2::new(c.x - 5.0, c.y - 5.5), 1.5, s);
            p.add(PathShape::line(vec![Pos2::new(c.x, c.y - 2.0), Pos2::new(c.x + 5.0, c.y - 5.0), Pos2::new(c.x + 5.0, c.y - 6.0)], s));
            p.rect_stroke(Rect::from_center_size(Pos2::new(c.x + 5.0, c.y - 7.2), Vec2::splat(3.0)), 0.0, s, egui::StrokeKind::Middle);
            p.add(PathShape::convex_polygon(
                vec![Pos2::new(c.x - 2.2, c.y - 8.0), Pos2::new(c.x + 2.2, c.y - 8.0), Pos2::new(c.x, c.y - 11.0)],
                color,
                Stroke::NONE,
            ));
        }
        "Bluetooth" => {
            let pts = [(-4.5, -4.5), (4.5, 4.5), (0.0, 9.0), (0.0, -9.0), (4.5, -4.5), (-4.5, 4.5)];
            p.add(PathShape::line(pts.iter().map(|(x, y)| Pos2::new(c.x + x, c.y + y)).collect(), s));
        }
        _ => {
            // Wi-Fi: three arcs opening upwards over a dot.
            let base = Pos2::new(c.x, c.y + 7.0);
            for r in [5.0, 9.0, 13.0] {
                p.add(PathShape::line(arc(base, r, -135.0, -45.0), s));
            }
            p.circle_filled(base, 1.8, color);
        }
    }
}
