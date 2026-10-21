---
id: changelog
summary: Full history, newest first, reconstructed from the development sessions. Older than LATEST.md. Exact days before 2026-10-12 were not tracked.
updated: 2026-10-21
sources: []
---
# Changelog (older updates; append-only)
Entries move here from LATEST.md automatically (`okf.py log`). Day granularity for 10-12 and 10-13 is approximate.

## 2026-10-18 · Agent: start when I log in (autostart) + start minimised
- files: agent/src/autostart.rs, agent/src/gui.rs, agent/src/main.rs, output/desk_ctrl_agent
- docs: AGENT, FEATURES
- tests: agent 65 pass (6 new, temp XDG_CONFIG_HOME)
- note: Settings window not looked at on screen (no click tool here) and a real login not tried (needs a restart); autostart points at the running program

## 2026-10-17 · Voice: no response fixed (CPU quota starved the engine), slow-computer hint
- files: agent/src/voice.rs, agent/voice/voice_helper.py, mobile/lib/voice.dart, mobile/test/voice_test.dart, mobile/test/fake_agent.dart, output/desk_ctrl_agent, output/voice_helper.py, output/desk_ctrl.apk
- docs: AGENT, KNOWN
- tests: agent 59 pass, phone 205 pass; Whistle timed on the SSH box with and without core pinning; APK installed
- note: not re-run on the dev machine (models froze it twice); user must restart the agent

## 2026-10-17 · Voice: all touchpad + round-menu options, safety limits, Needle guessing off by default
- files: mobile/lib/voice_commands.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/test/voice_commands_test.dart, mobile/test/voice_test.dart, agent/src/voice.rs, agent/voice/voice_helper.py, output/desk_ctrl_agent, output/voice_helper.py
- docs: FEATURES, SETTINGS, AGENT, KNOWN
- tests: phone 204 pass, agent 59 pass; APK installed
- note: Needle with the enlarged tool list was NOT tested (the test froze the dev machine a second time); the cause of the freezes is still unknown

## 2026-10-17 · Voice: RuntimeError (empty Needle model file) fixed, helper self-heals
- files: agent/voice/voice_helper.py, agent/src/voice.rs, output/voice_helper.py, output/desk_ctrl_agent
- docs: KNOWN
- tests: agent 58 pass; real Needle verified here: 124-179 ms per guess
- note: user must restart the agent to get the new helper script (the agent rewrites it at start)

## 2026-10-17 · Voice screen: dictation and commands (Whistle + Needle 3)
- files: agent/src/voice.rs, agent/src/server.rs, agent/src/bluetooth.rs, agent/src/main.rs, agent/voice/voice_helper.py, agent/voice/setup_voice.sh, mobile/lib/voice.dart, mobile/lib/voice_commands.dart, mobile/lib/voice_screen.dart, mobile/lib/links.dart, mobile/lib/connection.dart, mobile/lib/modes.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/Mic.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/MainActivity.kt
- docs: FEATURES, PROTOCOL, AGENT, MOBILE, SETTINGS, OPERATIONS, TESTING, DECISIONS, KNOWN, INDEX
- tests: phone 201 pass, agent 57 pass; helper checked on a second machine over SSH; APK built, NOT installed (no phone attached)
- note: microphone and the full chain untested on a real phone; phase 5 (engine on the phone) not done; user must run setup_voice.sh on the computer and restart the agent

## 2026-10-17 · Voice PoC results (Whistle + Needle on a second machine)
- files: tools/voice_poc/setup.sh, tools/voice_poc/README.md, output/voice_poc.zip
- docs: KNOWN
- tests: PoC run over SSH on a 4-core 2012 AMD machine: all steps ok
- note: see KNOWN.md voice section; no app code written

## 2026-10-16 · Voice PoC package (Whistle + Needle)
- files: tools/voice_poc/*, output/voice_poc.zip
- docs: KNOWN
- tests: scripts syntax-checked only; Needle step NOT run (it froze the dev machine)
- note: Whistle measured: 14-30 ms short clips, 0.43 s for 6 s, 0.8 s for 15 s; keywords fix 'refresh'/'undo' not 'copy'/'close'. Android engine lib is published (android-arm64). Needle results pending from another machine

## 2026-10-16 · Trackpad motion cursor: tilt via accelerometer (phone has no gyroscope)
- files: mobile/lib/motion_cursor.dart, mobile/lib/pad_screen.dart, mobile/lib/settings_sheet.dart, mobile/test/motion_cursor_test.dart, mobile/test/pad_motion_test.dart
- docs: FEATURES, SETTINGS, KNOWN, DECISIONS, MOBILE
- tests: phone tests pass; APK installed
- note: feel unverified on the real phone (screen locked); turning without tilting (yaw) no longer moves the cursor

## 2026-10-16 · Round button: no tooltip on hold
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart
- docs: FEATURES
- tests: phone 178 pass; APK installed
- note: tooltip removed (it popped up on long press)

## 2026-10-16 · Round button changes colour while held/open
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart
- docs: FEATURES
- tests: phone 178 pass; APK installed
- note: not seen on the phone

## 2026-10-16 · Fix: connection icon stuck in the side-bar layout (const widgets)
- files: mobile/lib/main.dart, mobile/test/transport_icon_test.dart
- docs: FEATURES
- tests: phone 178 pass; new test fails without the fix; APK installed
- note: root cause of the stuck USB icon; the USB_STATE listener from the previous entry stays as a faster drop

## 2026-10-16 · USB unplug: link dropped at once from Android's USB state
- files: mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/MainActivity.kt, mobile/lib/usb_pairing.dart, mobile/lib/links.dart, mobile/lib/connection.dart, mobile/lib/main.dart, mobile/test/transport_icon_test.dart, mobile/test/fake_agent.dart
- docs: FEATURES, TESTING
- tests: phone 177 pass; APK installed, app starts
- note: Cause of the stuck USB icon on a real cable not reproduced (unplug cannot be done from here; logic worked in tests). Needs the user's confirmation on a real unplug. Phone Wi-Fi was OFF during my checks

## 2026-10-16 · Test: icon goes USB -> Wi-Fi when the cable is pulled
- files: mobile/test/transport_icon_test.dart
- docs: TESTING
- tests: phone 175 pass
- note: no app change needed; not checked on a real cable (no phone attached)

## 2026-10-16 · Round menu: Close application option
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart, mobile/test/edit_menu_custom_test.dart
- docs: FEATURES
- tests: phone 174 pass
- note: Alt+F4 on the focused window; APK not installed if no phone

## 2026-10-16 · Round menu: Open terminal option
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart, mobile/test/edit_menu_custom_test.dart
- docs: FEATURES
- tests: phone 174 pass
- note: Ctrl+Alt+T; works where the desktop has that shortcut; saved custom layouts need Add > Open terminal

## 2026-10-16 · Copy on select with Copied message (setting)
- files: mobile/lib/connection.dart, mobile/lib/main.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/test/copy_on_select_test.dart
- docs: FEATURES, SETTINGS
- tests: phone 174 pass
- note: Ctrl+Insert, not Ctrl+C; not tried on the real phone

## 2026-10-16 · Test: connection icon follows fail-over
- files: mobile/test/transport_icon_test.dart
- docs: TESTING
- tests: phone 170 pass (new widget test)
- note: no app change: fail-over and icon already worked; Wi-Fi silent drop takes up to 3.5 s to detect

## 2026-10-16 · Offline: whole app is explorable
- files: mobile/lib/main.dart, mobile/lib/devices_screen.dart, mobile/test/offline_explore_test.dart
- docs: FEATURES
- tests: phone 169 pass
- note: APK built, not installed (no phone)

## 2026-10-16 · App keeps looking for the agent after start
- files: mobile/lib/connection.dart, mobile/test/wait_for_agent_test.dart, mobile/test/fake_agent.dart
- docs: FEATURES
- tests: phone 168 pass
- note: Same saved IP only: if the computer's IP changed it is not found (no discovery yet). APK not installed (no phone)

## 2026-10-16 · Round menu: a row fills the whole quarter
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart, mobile/test/edit_menu_custom_test.dart
- docs: FEATURES
- tests: phone 166 pass
- note: APK built, not installed (no phone)

## 2026-10-16 · Round menu fully customisable in Settings
- files: mobile/lib/edit_menu.dart, mobile/lib/edit_menu_editor.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/test/edit_menu_custom_test.dart
- docs: FEATURES, SETTINGS, MOBILE
- tests: phone 165 pass
- note: APK built, not installed (no phone attached)

## 2026-10-16 · Edit menu: third row with Refresh (F5)
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart
- docs: FEATURES, MOBILE
- tests: phone 162 pass; agent unchanged (45)
- note: rows are 80 px deep now (reach 296); APK built but not installed (no phone attached)

## 2026-10-14 · OKF created: documentation set, LATEST/CHANGELOG, tool
- files: okf/*, CLAUDE.md
- docs: INDEX, OKF, LATEST
- note: every later task adds an entry with okf.py log; root CLAUDE.md points agents to okf/INDEX.md

## 2026-10-14 · Agent window rebuilt to match agent_ui.png
- files: agent/src/gui.rs, agent/src/look.rs (new), agent/src/main.rs
- docs: AGENT
- tests: agent 45 pass; window checked by screenshot (Connect, Settings, Log)
- note: names are generic ("Phone N", "USB device"); icons are painted; Noto Sans loaded if present; window 620x400

## 2026-10-14 · Agent: Connect and Devices tabs merged, DESK_NO_USB added
- files: agent/src/gui.rs, agent/src/server.rs
- docs: AGENT
- note: a test window paired the real phone over USB and overwrote the user's "Computer 2" (same computer id); repaired with `adb reconnect`; hence `DESK_NO_USB=1` and rule 5 in INDEX

## 2026-10-14 · Edit menu: stays open for repeated taps, hold repeats Backspace/Delete/Enter
- files: mobile/lib/edit_menu.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/test/edit_menu_test.dart
- docs: FEATURES, SETTINGS, DECISIONS
- tests: phone 162 pass; verified on the phone against a fake recording agent (3 taps = 3 presses, 2 s hold = 35 presses, idle close 6 s)
- note: new setting `editMenuStayOpen` (default true)

## 2026-10-14 · Edit menu rebuilt as a single overlay (tap and hold share one close path)
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart
- docs: MOBILE, DECISIONS
- note: hold + lift on the button leaves the menu open; hold + drag + lift on an option runs it and closes

## 2026-10-14 · Motion cursor: "also without touching the screen"
- files: mobile/lib/pad_screen.dart, mobile/lib/motion_cursor.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart
- docs: FEATURES, SETTINGS, KNOWN
- tests: phone tests pass (pad_motion_test, motion_cursor_test extended)
- note: gain raised 1600 -> 5000 px/rad plus a x2.5 boost for quick turns after "cursor moves very small"; real-phone feel still unverified

## 2026-10-14 · Settings: Screens section crash fixed
- files: mobile/lib/settings_sheet.dart, mobile/test/screens_section_test.dart
- docs: DECISIONS
- note: ExpansionTile `PageStorageKey` + nested Scrollable cast a bool as a scroll offset; isolated with its own `PageStorage`

## 2026-10-14 · Trackpad: three-dots settings button removed
- files: mobile/lib/pad_screen.dart, mobile/test/pad_zones_test.dart
- docs: FEATURES
- note: settings reachable from the rail's tune icon (scoped to the screen)

## 2026-10-14 · Trackpad motion cursor (air mouse)
- files: mobile/lib/motion_cursor.dart (new), mobile/lib/pad_screen.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/test/motion_cursor_test.dart, mobile/test/pad_motion_test.dart
- docs: FEATURES, SETTINGS, MOBILE
- note: settings padMotion / padMotionSpeed / padMotionInvert; one finger on the pad is the clutch by default

## 2026-10-14 · USB: Wi-Fi + Bluetooth set up over the cable, computer ids, no duplicates
- files: agent/src/identity.rs (new), agent/src/server.rs, agent/src/usb.rs, mobile/lib/connection.dart, mobile/lib/links.dart, mobile/lib/settings.dart, mobile/lib/device_form.dart, mobile/test/usb_test.dart
- docs: PROTOCOL, ARCHITECTURE, SETTINGS, DECISIONS, FEATURES
- tests: phone 132+, agent 45 pass; checked on the real phone (USB + Wi-Fi, token change = same entry)
- note: frame `0x14`; `usbSync` setting; `findSame`/`mergeInto`/`dedupeAll`; merges serialized after a race deleted both entries

## 2026-10-14 · USB cable as a third transport (auto pair, no QR)
- files: agent/src/usb.rs (new), mobile/lib/usb_pairing.dart (new), mobile/lib/links.dart, mobile/lib/connection.dart, AndroidManifest.xml, MainActivity.kt, output/setup_laptop.sh
- docs: PROTOCOL, ARCHITECTURE, AGENT, MOBILE, FEATURES, OPERATIONS
- tests: agent +8 usb tests (fake adb); phone usb_test; verified on the phone (plug-in pairs, tunnel restored, pointer moves over USB)

## 2026-10-14 · Edit menu: two rings, terminal copy/paste, Enter/Backspace/Delete, black and white, rotation-aware
- files: mobile/lib/edit_menu.dart, mobile/test/edit_menu_test.dart, mobile/test/layout_rotation_test.dart
- docs: FEATURES, MOBILE
- note: fan opens toward the screen middle (bar can be on the right), closes on rotation
## 2026-10-14 · Earlier the same day
- Auto keyboard v3: agent reports typeable / not typeable for every focus change (`0x13 [0|1]`); phone waits 700 ms during window/tab slides and the last place decides; option "Only when I click a field" (`autoKeyboardOnClick`) with click timer; verified on the phone with real apps (editor, file manager, terminal, Firefox tabs).
- Agent focus: front-window app searched for the focused widget (AT-SPI tree), tiny trees inconclusive; X11 window poll; Obsidian-like apps fall back to class list.
- Window-switch guard (`WindowSwitchGuard`) was added then removed when the user chose: option 1 (auto) or option 2 (click only).
- Browser tab switching on the bottom slider (centre icon toggles windows <-> tabs, Ctrl+Tab), setting `padTabSwitch`; auto-keyboard ignores focus bounce during tab slides.
- Settings sheet scoped per screen ("All settings" button), phone-screen brightness per screen, themes (soft / amoled / tinted + accent).

## 2026-10-13 · Approximate day
- Edge controls v2: window switcher on the bottom edge (Alt+Tab / Alt+Shift+Tab, hold = switcher open), mute tap + crossed-speaker icon, touchpad on/off moved to Settings, settings button on the pad (later removed).
- Auto keyboard v1/v2: AT-SPI focus events -> `0x13`; Terminal/entry roles; window-class fallback; setting `autoKeyboard`.
- Agent: volume/brightness percentages (`levels.rs`, `0x12`), "brightness not supported" message; seek speed setting.

## 2026-10-12 · Approximate day
- Trackpad top edge: seek forward/back (arrows) by default, ⏮ ⏭ track buttons, single ▶/⏸ toggle icon, hold ⏪ ⏩ repeat, speed setting; next/previous track mode kept.
- Settings reorganised into collapsible sections; theme work; desktop agent window: tabs, compact two-column layout.
- Windows support question answered (not supported; list of what a port needs).

## Before 2026-10-12 · Foundation (days not tracked)
- Project created: Flutter app + Rust agent; keyboard, trackpad, mouse (tilt) screens; token pairing over Wi-Fi WebSocket; uinput injection.
- QR pairing + scanner; agent GUI (egui) with Stop/Reconnect and port-in-use help (`portowner.rs`); fixes: bind-first start, "Address already in use" half-start.
- Bluetooth transport (RFCOMM, BlueZ Profile1, fixed channel + SDP record, non-blocking socket fix); Wi-Fi <-> Bluetooth switching without reconnect.
- Multi-computer: several sessions connected, instant switching, last connected remembered; setup script (udev uinput rule + launcher).
- Lock-key lights (Caps/Num/Scroll) from `/sys/class/leds`; Fn row / brightness / media keys; keyboard options (F-row switch, Fn key, joined Backspace/Del, shift legends, arrow cluster).
- Notch/side-bar option, mode button (tap cycles, long-press menu, order editor), mouse/pad tab switches.
- Dual-link fail-over with heartbeat + keep-alive (3.5 s dead detection, held-key release), backward compatible with old apps/agents.
- Trackpad: small Left/Right bar option, screenshot gesture, edge control zones (volume left, brightness right, media top) with HUD.
