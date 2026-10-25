#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

#[cfg(unix)]
mod autostart;
mod audio;
#[cfg(windows)]
#[path = "autostart_win.rs"]
mod autostart;
#[cfg(unix)]
mod bluetooth;
#[cfg(windows)]
#[path = "bluetooth_win.rs"]
mod bluetooth;
#[cfg(unix)]
mod focus;
#[cfg(windows)]
#[path = "focus_win.rs"]
mod focus;
mod gui;
mod identity;
mod look;
mod hid;
mod inject;
mod leds;
mod levels;
#[cfg(unix)]
mod portowner;
#[cfg(windows)]
#[path = "portowner_win.rs"]
mod portowner;
mod server;
mod tokenstore;
mod tray;
mod usb;
#[cfg(windows)]
mod winproc;
mod voice;

use server::{make_token, Server, DEFAULT_PORT};

fn main() -> eframe::Result<()> {
    let port: u16 = std::env::var("DESK_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(DEFAULT_PORT);
    // The token stays the same across restarts, so phones paired once stay paired (tokenstore.rs).
    let token = std::env::var("DESK_TOKEN").unwrap_or_else(|_| tokenstore::load_or_create(make_token));
    // Autostart that points at another copy of the agent (replaced, moved) is pointed at this one.
    if let Ok(exe) = autostart::current_exe() {
        autostart::refresh(&exe);
    }
    voice::Engine::prepare(); // puts the voice helper script where setup_voice.sh's Python expects it
    let mut server = Server::new(token.clone());

    if std::env::args().any(|a| a == "--headless") {
        println!("desk_ctrl agent (headless) - pairing token: {token}");
        server.start(port);
        let (error, owner) = {
            let s = server.shared.lock().unwrap();
            (s.error.clone(), s.port_owner.clone())
        };
        if let Some(e) = error {
            eprintln!("{e}");
            if let Some(pid) = owner.and_then(|o| o.pid) {
                eprintln!("Stop it with:  kill {pid}");
            }
            std::process::exit(1);
        }
        loop {
            std::thread::sleep(std::time::Duration::from_secs(3600));
        }
    }

    // The window is drawn with wgpu (Vulkan / DX12 / Metal); on Windows, if that cannot start (an old
    // graphics driver, a virtual machine), OpenGL is tried next. The server waits in a cell so the
    // second try still has it when the first failed before building the window.
    let server = std::rc::Rc::new(std::cell::RefCell::new(Some(server)));
    #[cfg_attr(not(windows), allow(unused_mut))]
    let mut renderers = vec![eframe::Renderer::Wgpu];
    #[cfg(windows)]
    renderers.push(eframe::Renderer::Glow);
    let mut last = Ok(());
    for renderer in renderers {
        let options = eframe::NativeOptions {
            viewport: eframe::egui::ViewportBuilder::default()
                .with_inner_size([720.0, 420.0])
                .with_min_inner_size([680.0, 380.0])
                .with_title("ViL Agent")
                .with_icon(eframe::icon_data::from_png_bytes(include_bytes!("../../branding/vil-icon-256.png")).expect("ViL icon")),
            renderer,
            ..Default::default()
        };
        let cell = server.clone();
        last = eframe::run_native(
            "ViL Agent",
            options,
            Box::new(move |cc| {
                look::install(&cc.egui_ctx);
                let server = cell.borrow_mut().take().expect("the server is taken once");
                let mut app = gui::App::new(server, port);
                app.start_minimized = std::env::args().any(|a| a == autostart::MINIMIZED_FLAG);
                Ok(Box::new(app))
            }),
        );
        match &last {
            Ok(()) => break,
            // The window was built (the server is taken) and then failed: do not start a second one.
            Err(_) if server.borrow().is_none() => break,
            Err(e) => eprintln!("could not draw the window with {renderer:?}: {e}"),
        }
    }
    last
}
