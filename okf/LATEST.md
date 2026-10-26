---
id: latest
summary: The 12 newest updates, newest first (what changed, files, tests, caveats). Read this to know the current state of work.
updated: 2026-10-26
sources: []
---
# Latest updates (newest first; older ones are in CHANGELOG.md)
Entry format: `## date · title` + `files:` `docs:` `tests:` `note:`. Add entries with `python3 okf/okf.py log ...`.

## 2026-10-26 · Reduce Remote Audio burst stutter and playback latency
- files: agent/src/audio.rs, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/RemoteAudio.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PcmPump.kt, tools/audio/PcmPumpTest.kt, tools/audio/test_pcm_pump.py, README.md
- docs: AGENT, MOBILE, SETTINGS, FEATURES, TESTING, KNOWN, PROTOCOL, ARCHITECTURE
- tests: Flutter 253 passed; Linux agent 77 passed; native PCM prebuffer/partial-write/continuity/error tests passed; Android and Linux/Windows release builds passed
- note: Pulse server unavailable in shell; live listening and exact AV latency not measured; restart updated desktop agent for capture timing fix

## 2026-10-25 · Add Remote Audio Output
- files: README.md, agent/Cargo.toml, agent/Cargo.lock, agent/src/main.rs, agent/src/server.rs, agent/src/audio.rs, mobile/lib/settings.dart, mobile/lib/connection.dart, mobile/lib/main.dart, mobile/lib/settings_sheet.dart, mobile/lib/remote_audio.dart, mobile/lib/remote_audio_sheet.dart, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/MainActivity.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/RemoteAudio.kt, mobile/test/fake_agent.dart, mobile/test/remote_audio_test.dart, output/setup_laptop.sh, output/README_windows.txt, output/desk_ctrl.apk, output/desk_ctrl_agent, output/desk_ctrl_agent.exe
- docs: INDEX, ARCHITECTURE, PROTOCOL, AGENT, MOBILE, SETTINGS, FEATURES, TESTING, KNOWN, OPERATIONS
- tests: Flutter 253 passed; Remote Audio 5 passed; analyzer 12 existing infos; Linux agent 77 passed; Windows Wine 32 passed; Linux/Windows releases and 71.4 MB APK built; APK installed; phone layout checked
- note: PCM audio verified with fake agents; real Linux/Windows/Android audio hardware not exercised; Bluetooth-only audio unavailable; Windows source requires Also play on source

## 2026-10-24 · Refine Mobile controls after UI inspection
- files: mobile/lib/mobile_screen.dart, mobile/test/mobile_screen_test.dart
- docs: FEATURES, MOBILE, TESTING
- tests: Flutter 248 passed; focused 5 passed; analyzer 12 existing infos; release APK built and installed; portrait/landscape default and swapped layouts checked
- note: Landscape controls now end before the media strip; portrait punctuation row remained readable and unclipped

## 2026-10-24 · Add punctuation row to Mobile keyboard
- files: README.md, mobile/lib/keyboard_screen.dart, mobile/test/mobile_screen_test.dart
- docs: INDEX, FEATURES, MOBILE, SETTINGS, TESTING
- tests: Flutter 248 passed; focused 5 passed; analyzer 12 existing infos; release APK built
- note: Only Mobile portrait compact keyboard changed; APK installation and visual check pending because no adb device is attached

## 2026-10-24 · Add Mobile section swap button
- files: README.md, mobile/lib/mobile_screen.dart, mobile/test/mobile_screen_test.dart
- docs: FEATURES, MOBILE, SETTINGS, TESTING
- tests: Flutter 247 passed; focused 4 passed; analyzer 12 existing infos; release APK built
- note: APK installation and on-phone visual check pending because no adb device is attached

## 2026-10-23 · Move Mobile landscape controls to top edge
- files: mobile/lib/mobile_screen.dart, mobile/test/mobile_screen_test.dart
- docs: FEATURES, MOBILE, TESTING
- tests: Flutter 247 passed; focused 4 passed; release APK built and installed; landscape and portrait screenshots checked; analyzer 12 existing infos
- note: Landscape uses 28 dp controls with 14 dp icons; portrait layout unchanged

## 2026-10-23 · Align Mobile controls by orientation
- files: mobile/lib/mobile_screen.dart, mobile/test/mobile_screen_test.dart
- docs: FEATURES, MOBILE, TESTING
- tests: Flutter 247 passed; focused 4 passed; release APK built and installed; portrait and landscape screenshots checked; analyze 12 existing infos
- note: Portrait buttons align with the left volume strip; landscape buttons sit side by side at top left

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

