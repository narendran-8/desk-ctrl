---
id: latest
summary: The 12 newest updates, newest first (what changed, files, tests, caveats). Read this to know the current state of work.
updated: 2026-10-23
sources: []
---
# Latest updates (newest first; older ones are in CHANGELOG.md)
Entry format: `## date · title` + `files:` `docs:` `tests:` `note:`. Add entries with `python3 okf/okf.py log ...`.

## 2026-10-23 · Add Computer to the mode switcher
- files: mobile/lib/modes.dart, mobile/lib/main.dart, mobile/lib/devices_screen.dart, mobile/lib/mode_button.dart, mobile/lib/modes_editor.dart, mobile/lib/settings_sheet.dart, mobile/test
- docs: FEATURES, MOBILE, SETTINGS
- tests: Flutter tests: 238 passed including Computer mode cycle and device switching; release APK built and adb install succeeded
- note: Computer is always available in the mode order; saved mode orders are completed without duplicates. Flutter analyze still reports 13 pre-existing curly-braces lint infos.

## 2026-10-23 · Use transparent ViL icon on Android and desktop
- files: branding, mobile/android/app/src/main/res, output/vil-icon.png
- docs: MOBILE, AGENT, OPERATIONS
- tests: Flutter tests: 238 passed; release APK built and installed successfully; Linux agent release build passed; adb device 863d0058304830363451066c2082bb installed APK; cargo test blocked by environment-dependent Bluetooth/port tests
- note: Flutter analyze still reports 13 pre-existing curly-braces lint infos; no icon-related diagnostics. Master PNG and generated Android/desktop/Windows assets have alpha transparency.

## 2026-10-21 · Add readable build and usage README
- files: README.md, okf/INDEX.md
- docs: INDEX, OPERATIONS
- tests: git diff --check passed; README commands and links reviewed
- note: Root README now documents setup, compilation, pairing, usage, limitations, testing, and troubleshooting.

## 2026-10-21 · Upload project to private GitHub
- files: .gitignore, .git, okf/LATEST.md
- docs: INDEX, OPERATIONS
- tests: OKF check passed; private GitHub repository created and main pushed
- note: Repository: https://github.com/narendran-8/desk-ctrl

## 2026-10-21 · Initialize local Git tracking for the full ViL project
- files: .gitignore, agent, mobile, branding, tools, okf, output, back_dir/memory
- docs: INDEX, OPERATIONS
- tests: Git index reviewed: source/docs/assets and four memory notes staged; builds and scratch excluded
- note: Root repository on main; no earlier usable project history existed. An empty agent/.git metadata directory was preserved; output APK and agent executables are ignored as reproducible build artifacts.

## 2026-10-21 · ViL name and approved binary bow icon applied
- files: branding, tools/prepare_branding.py, tools/tray_smoke.py, mobile/lib/main.dart, mobile/android/app/src/main/AndroidManifest.xml, mobile/android/app/src/main/res, agent/build.rs, agent/vil.rc, agent/src/main.rs, agent/src/gui.rs, agent/src/tray.rs, agent/src/autostart.rs, agent/src/bluetooth.rs, agent/src/usb.rs, agent/src/portowner.rs, agent/src/portowner_win.rs, output/setup_laptop.sh, output/vil-icon.png, output/desk_ctrl.apk, output/desk_ctrl_agent, output/desk_ctrl_agent.exe
- docs: INDEX, MOBILE, AGENT, OPERATIONS
- tests: 238 phone tests pass; 7 autostart tests pass; ViL tray integration passes; Android/Linux/Windows releases built; APK label ViL verified; Windows icon resource present
- note: APK not installed: no phone connected. Existing package/config/pairing IDs and output filenames retained for compatibility. Windows native icon appearance not checked on a Windows PC.

## 2026-10-21 · Window close hides to tray; tray Close application exits
- files: agent/src/gui.rs, agent/src/tray.rs, tools/tray_smoke.py, output/desk_ctrl_agent, output/desk_ctrl_agent.exe
- docs: AGENT, FEATURES, TESTING
- tests: Linux and Windows release builds pass; isolated Linux minimize/show/window-close/show/full-exit test passes
- note: Enable Minimize to tray in Settings. Native Windows tray behavior remains unverified.

## 2026-10-21 · Desktop agent: optional minimize to tray
- files: agent/Cargo.toml, agent/Cargo.lock, agent/src/main.rs, agent/src/gui.rs, agent/src/tray.rs, tools/tray_smoke.py, output/desk_ctrl_agent, output/desk_ctrl_agent.exe
- docs: AGENT, FEATURES, SETTINGS, TESTING
- tests: 75 Linux tests pass (74 together plus isolated retry); Linux tray hide/restore/quit integration passes; Linux and Windows release builds pass
- note: Windows notification area not tested on a real PC. Linux requires a StatusNotifier tray host. Close still quits; backup in back_dir is unchanged.

## 2026-10-21 · Project backup created in back_dir
- files: back_dir, memory
- docs: OKF
- tests: backup verified: 225 files, 144M
- note: Generated build caches and Git metadata were excluded; source, output, tools, OKF, and four memory files were copied

## 2026-10-19 · Camera side (flip left/right) tried and reverted at the owner's request
- files: mobile/lib/settings.dart, mobile/lib/main.dart, mobile/lib/mouse_screen.dart, mobile/lib/settings_sheet.dart
- docs: FEATURES
- tests: phone 238 pass; APK built, NOT installed (no phone attached)
- note: nothing of it is left in the code; the notch bar (Auto / On / Off) from the previous entry stays

## 2026-10-19 · Notch bar: automatic, fits any camera hole (smaller icons, second line)
- files: mobile/lib/notch_layout.dart, mobile/lib/main.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/test/notch_matrix_test.dart, mobile/test/notch_auto_test.dart, mobile/test/notch_layout_test.dart
- docs: FEATURES, SETTINGS, DECISIONS, KNOWN
- tests: phone 238 pass; APK built, NOT installed (no phone attached)
- note: layout verified by tests and rendered pictures for 8 hole shapes, not on a real second phone

## 2026-10-19 · Agent window: clean alignment (one grid, equal pills, shared table columns, scrolling Settings)
- files: agent/src/gui.rs, agent/src/look.rs, agent/src/main.rs, agent/src/autostart.rs, agent/src/autostart_win.rs, output/desk_ctrl_agent, output/desk_ctrl_agent.exe
- docs: AGENT, KNOWN, TESTING
- tests: agent 74 pass (Linux), 29 pass (Windows build under Wine); window checked by screenshots: default, devices, settings, log, port-busy
- note: autostart refresh no longer lets a demo copy hijack the entry (it had: repaired); copy/paste investigation interrupted, see KNOWN

