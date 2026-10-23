---
id: latest
summary: The 12 newest updates, newest first (what changed, files, tests, caveats). Read this to know the current state of work.
updated: 2026-10-23
sources: []
---
# Latest updates (newest first; older ones are in CHANGELOG.md)
Entry format: `## date · title` + `files:` `docs:` `tests:` `note:`. Add entries with `python3 okf/okf.py log ...`.

## 2026-10-23 · Fix Mobile media controls and align Mobile buttons
- files: README.md, mobile/lib/edge_zones.dart, mobile/lib/mobile_screen.dart, mobile/lib/pad_screen.dart, mobile/test/mobile_screen_test.dart, mobile/test/pad_zones_test.dart
- docs: INDEX, FEATURES, MOBILE, SETTINGS, TESTING
- tests: Flutter 247 passed; targeted 26 passed; APK built and installed; portrait/landscape visually checked; analyze 12 existing infos
- note: Real computer media playback was not exercised; routing verified against recording fake agent and Android channel mock

## 2026-10-23 · Fix track-mode skip-button tap on trackpad top strip
- files: mobile/lib/pad_screen.dart, mobile/test/pad_zones_test.dart
- docs: MOBILE, TESTING
- tests: Flutter 246 passed
- note: In track mode the _skip flag was never set so tapping the skip_previous/skip_next icons did nothing; removing the TopEdgeMode.seek guard fixes it for both modes

## 2026-10-23 · Support portrait in combined Mobile mode
- files: mobile/lib/mobile_screen.dart, mobile/lib/keyboard_screen.dart, mobile/lib/pad_screen.dart, mobile/lib/edge_zones.dart, mobile/test/mobile_screen_test.dart, README.md
- docs: INDEX, MOBILE, FEATURES, TESTING
- tests: Flutter 245 passed; portrait APK built; intermediate build checked on phone; final APK install pending because adb device disappeared; analyze has 12 existing style infos
- note: Rotate icon switches orientation; portrait keyboard keeps phone-sized QWERTY and shortcuts.

## 2026-10-23 · Add combined Mobile keyboard and touchpad screen
- files: mobile/lib/mobile_screen.dart, mobile/lib/modes.dart, mobile/lib/modes_editor.dart, mobile/lib/main.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/lib/edge_zones.dart, mobile/test/mobile_screen_test.dart, mobile/test/modes_test.dart, mobile/test/modes_editor_test.dart, mobile/test/mode_tap_test.dart, mobile/test/mode_button_test.dart, mobile/test/voice_screen_test.dart, mobile/test/auto_keyboard_test.dart, README.md
- docs: INDEX, MOBILE, SETTINGS, FEATURES, TESTING
- tests: Flutter 244 passed; APK built and installed; Mobile layout and settings checked on phone; analyze has 12 existing style infos
- note: Combined screen uses existing touchpad and keyboard controls; old saved mode orders append Mobile.

## 2026-10-23 · Show phone volume and brightness percentages
- files: mobile/lib/pad_screen.dart, mobile/lib/phone_media.dart, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/MainActivity.kt, mobile/test/phone_media_test.dart
- docs: FEATURES, MOBILE, TESTING
- tests: Flutter 241 passed; Android release APK built and installed; phone showed volume 46% and brightness 95%; analyze only 13 existing style infos
- note: Brightness percentage is for the ViL window; test adjustments were reversed and Mobile mode left off.

## 2026-10-23 · Trackpad Mobile media controls
- files: mobile/lib/pad_screen.dart, mobile/lib/phone_media.dart, mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/MainActivity.kt, mobile/test/phone_media_test.dart
- docs: INDEX, FEATURES, MOBILE, SETTINGS, TESTING
- tests: Flutter 241 passed; Android release APK built and installed; phone toggle visually checked; analyze only 13 existing style infos
- note: Android media keys target the active phone media session; browser seek support varies. Brightness adjusts the ViL window, not system-wide brightness.

## 2026-10-23 · Separate computer switching from the transport glyph
- files: mobile/lib/main.dart, mobile/test/computer_button_test.dart
- docs: INDEX, FEATURES, MOBILE, TESTING
- tests: Flutter 240 passed; targeted mixed-medium and single-device failover tests passed; APK built, installed, and checked on phone; analyze only 13 pre-existing style infos
- note: With multiple connected computers the link glyph stays stable; actual medium remains in its tooltip and sheet.

## 2026-10-23 · Identify connected computers by icon colour
- files: mobile/lib/device_color.dart, mobile/lib/main.dart, mobile/lib/devices_screen.dart, mobile/test/computer_button_test.dart
- docs: FEATURES, MOBILE, TESTING
- tests: Flutter 239 passed; targeted gesture/icon test passed; APK built and installed; analyze has 13 pre-existing info lints
- note: Computer icon reflects active device; transport icon still reflects the active device medium.

## 2026-10-23 · Computer button switches live devices by tap gestures
- files: mobile/lib/connection.dart, mobile/lib/main.dart, mobile/test/computer_button_test.dart
- docs: INDEX, FEATURES, MOBILE, TESTING
- tests: Flutter 239 passed; release APK built and installed; analyze 13 pre-existing info lints; git diff --check passed
- note: Gestures switch only connected computers; long press opens the Computers sheet.

## 2026-10-23 · Revert Computer mode update
- files: mobile/lib, mobile/test, README.md
- docs: FEATURES, MOBILE, SETTINGS
- tests: Flutter tests: 238 passed; reverted APK built and installed successfully
- note: The mode switcher is restored to the previous Keyboard, Mousepad, Mouse, and optional Voice behavior.

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

