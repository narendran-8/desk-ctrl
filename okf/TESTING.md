---
id: testing
summary: How to run and write tests (phone + agent), the helpers, pitfalls, and the safe recipe for testing on the real phone.
updated: 2026-10-24
sources: [mobile/test/fake_agent.dart, mobile/test/usb_test.dart, mobile/test/edit_menu_test.dart, mobile/test/pad_motion_test.dart, agent/src/usb.rs]
---
# Testing

Tray integration: `xvfb-run -a dbus-run-session -- /usr/bin/python3 tools/tray_smoke.py agent/target/release/agent`. Uses an isolated config, bus, tray host and desktop; verifies registration, startup minimized hides the window, Show restores it, window close hides without exiting, Show restores again and Close application exits. USB and voice are disabled. Windows cross-compiles; native notification-area behavior still needs a Windows PC.

State: phone 248 tests pass; agent has 73 Linux tests (29 Windows tests under Wine at last check). Run: `cd mobile && flutter test` (~100 s) · `cd agent && cargo test`.

## Phone tests (mobile/test/*_test.dart)
Helpers in `fake_agent.dart`: `FakeAgent.start(token)` = WebSocket server on 127.0.0.1 (records frames as `"1,0,42"` strings in `received`, sends heartbeat,
`leds`, `info` (USB info frame), `report(vol,bright,muted)`, `textFocus({typeable,old})`, `sockets` list, `socket`), `FakeBt` (Bluetooth bridge, `bonded` list), `settle()`.
Sensors: mock `EventChannel('dev.fluttercommunity.plus/sensors/{gyroscope,accelerometer}')` with `MockStreamHandler.inline` (`onListen` must return void), events `[x,y,z,micros]`.
| Area | Files |
|---|---|
| links/fail-over | `failover_test`, `multi_device_test`, `device_status_test`, `bt_message_test` |
| computer button gestures | `computer_button_test` (previous/next live target, offline skip, long-press sheet, distinct computer colours, stable link glyph when switching Wi-Fi/Bluetooth computers, actual target medium in sheet) |
| USB, ids, dedupe | `usb_test`, `device_form_duplicate_test`, `pair_info_test` |
| trackpad | `pad_zones_test`, `pad_buttons_test`, `pad_motion_test`, `motion_cursor_test`, `edge_zones_test`, `screenshot_gesture_test` |
| phone media mode | `phone_media_test` mocks `deskctrl/phone_media` and checks toggle/routing, phone volume/brightness percentages, and Settings hiding the button; `mobile_screen_test` taps portrait play/pause and next icons against a recording fake agent, then toggles phone media and checks Android MethodChannel actions with no desktop key frames; portrait and landscape tests check the small buttons' vertical placement |

On-phone percentage check (2026-10-23): Mobile mode on, one left-edge volume step showed `Phone volume 46%`; one right-edge decrease showed `Phone brightness 95%`. Reversed the steps (volume returned to 40%, window brightness stepped back up) and switched Mobile mode off.
On-phone combined-screen check (2026-10-23): release APK installed; the mode button reached the new Mobile screen, showing a compact touchpad above all six keyboard rows with no clipped controls. Its scoped Settings sheet showed Keyboard controls. Only the mode and Settings buttons were touched; no input was sent to the computer. `mobile_screen_test` now also checks the portrait 5-row layout without overflow, alongside landscape.
Portrait Mobile check (2026-10-23): an intermediate release APK was installed and the phone showed a portrait touchpad above five readable keyboard rows with the rotate button. Its gesture help was crowded, so a shorter portrait-only message was added and all 245 tests passed. The final APK is at `output/desk_ctrl.apk`; the phone disconnected before the final install.
Mobile controls check (2026-10-23): updated APK installed; screenshots confirmed the small rotate and phone-media buttons align vertically with the volume strip in portrait and sit horizontally at the top left in landscape. The on-phone check only changed screen mode and orientation; media key actions were verified with the recording fake agent widget test.
Landscape refinement (2026-10-23): release APK installed; screenshot showed the 14 dp landscape icons in a 28 dp horizontal row against the touchpad's top edge, near the top media marks. Portrait screenshot confirmed its larger vertical buttons stayed in place. No control inputs were sent to a real computer.
Mobile section swap (2026-10-24): `mobile_screen_test` taps the swap button in portrait and landscape, verifies Keyboard moves above TouchPad, taps again, and verifies TouchPad returns above Keyboard. It also checks the swap control joins the vertical portrait control stack and horizontal landscape row. The APK was built, but the phone disconnected before installation.
Mobile punctuation row (2026-10-24): `mobile_screen_test` verifies the compact-only sixth row contains all 11 base punctuation keys and their 11 Shift symbols. The full 248-test suite passed; the release APK was installed and its portrait rows remained readable without clipping.
Mobile UI inspection (2026-10-24): installed the punctuation/swap APK and checked portrait default, portrait swapped, landscape default, and landscape swapped screens. Landscape exposed the left control row crowding the top media strip; the controls were moved into the unused corner and a geometry assertion now keeps the swap button before `EdgeZones.topFrom`. The rebuilt APK was installed and rechecked in all relevant layouts; controls and media marks no longer overlap. Mobile was left in its default trackpad-above-keyboard portrait state.
| menus/settings/layout | `edit_menu_test`, `settings_sheet_test`, `screens_section_test`, `layout_rotation_test`, `modes*_test`, `mode_button_test`, `notch_layout_test`, `mobile_screen_test` (combined layout, portrait/landscape section swap, compact punctuation row, persisted mode switch, scoped settings) |
| auto keyboard | `auto_keyboard_test` |
| keyboard | `arrow_cluster_test`, `delete_switch_test`, `shift_highlight_test` |

Pattern: real sockets need `tester.runAsync(() => Future.delayed(...))` to deliver; fake-time timers need `tester.pump(Duration)`; view `Size(1640,720)` @2.0 = 820x360 logical.

## Windows build tests (Wine)
`./tools/windows/build_windows.sh test` runs 29 agent tests under Wine (keys -> virtual keys, registry autostart, token file, lock lights, port owner, Wi-Fi server with `SendInput`). Wine reports every process id as 0 and its `netstat` has no pids, hence the `pid == 0` allowance in the port tests. Smoke test used: `agent.exe --headless` under Wine with `DESK_PORT`, `DESK_TOKEN`, `DESK_NO_USB`, a Python websocket client (token ok, wrong token refused, LED / info / level frames arrive, key / move / scroll frames accepted). GUI check: `Xvfb` + `wine` + `xwd` screenshot (wgpu fails there without DRI3, the OpenGL fallback draws the window).

## Agent window check
`/tmp/shot.sh`-style: `Xvfb :78`, `WGPU_BACKEND=gl <agent>`, `xwd -root`, convert with PIL; a Python websocket client connects to the agent (a client from the LAN address shows as a Wi-Fi phone, one from 127.0.0.1 as a USB device). Look at: default, devices connected, `DESK_SHOW=settings`, `DESK_SHOW=log`, port-busy error (start a second agent on the same port).

## Voice tests
Agent: fake shell helper (`voice::fake_engine`) over Wi-Fi and Bluetooth; never start the real Needle on the dev machine without limits (it froze it once; use `tools/voice_poc/run.sh` or the box over SSH). Phone: `FakeAgent.voiceText` answers a recording, `voiceIntent` an intent request; `FakeMic` (voice_test.dart). The helper's action list is cross-checked against the phone's phrase table in voice_commands_test.dart.

## Pitfalls
- Singletons (`Settings`, `Connection`) leak between tests: reset `SwitchGuard`, `Connection.lastClickAt`; `late` agent used in `tearDown` fails if a test never created it (use nullable).
- Lazy `ListView`: offscreen items are not built; use a tall view (`Size(1640,3200)`) or `scrollUntilVisible` + `ensureVisible`.
- `Connection` timers created inside `runAsync` are real-time (pump does not advance them).
- `pumpAndSettle` waits out SnackBars (3 s) - assert while they show, end with `pumpAndSettle(5 s)` to avoid "timer pending".
- Flaky once under load: `failover_test` (timing), agent `a_busy_port_leaves_the_server_startable` (port race). Re-run before suspecting code.
- Agent tests must never poll the cable: `Server.usb_auto` is false under `cfg!(test)`.
- usb tests use a fake `adb` shell script (`usb.rs` tests) recording calls.

## Real-phone testing - SAFE RECIPE (a phone tap can type on a real computer)
1. `adb devices` shows the phone (serial 863d0058304830363451066c2082bb, model 25028RN03I). If not: ask the user to plug in; do not guess.
2. Never use the user's computer as the target. Start a **recording fake agent** (python websockets on 127.0.0.1:8793, token `faketok`, replies `ok`, 1 s heartbeat `0x11`, logs frames
   `1/2 hi lo` to a file - the log file may contain NULs, read with `tr -d '\000'`), `adb reverse tcp:8793 tcp:8793`.
3. Add it as computer "ZZfake" in the app (form: tap field, `KEYCODE_MOVE_END` + 24x `KEYCODE_DEL`, `input text`, `KEYCODE_BACK` to hide the IME, ONE field at a time), then **make it Active and verify "Active" next to it before any key/click**.
4. Drive the UI with `adb shell input tap/swipe` only after a screenshot confirms the screen (rail side: count bright pixels top-left vs top-right; screen = keyboard if >55% of sampled pixels are lit).
5. Clean up: Forget ZZfake (⋮ at the row, Forget, confirm - check the dialog title), re-activate the user's computer, kill the fake by PID (`ss -ltnp`), `adb reverse --remove tcp:8793`, delete temp files.
Coordinates (landscape 1640x720 px, rail on the LEFT; mirrored x ≈ 1640-52 when the phone is turned): edit button (52,48), computers (52,143), transport (52,240), mode (52,576), settings tune (52,672).
2026-10-23 phone observation: two live computers ("Computer 2" USB + Wi-Fi, "box" Wi-Fi). Before the fix, tapping the computer icon changed the neighbouring USB glyph to Wi-Fi; after the fix, the computer icon changed teal/blue and the link glyph stayed fixed. The original computer was reselected after checking. No keys/clicks were sent to a computer.
Computers sheet: Add (1370,~102), row ⋮ at x=1332. `am start -n com.deskctrl.deskctrl/.MainActivity` (not `monkey`, it hangs). Rotation: `settings put system user_rotation 1|3` (restore `accelerometer_rotation 1`, `user_rotation 0`).
Desktop side checks: pointer position via Gdk (`Gdk.Display.get_default().get_default_seat().get_pointer().get_position()`), synthetic clicks via `Atspi.generate_mouse_event`, `wmctrl -a "title"` to switch windows, `xprop`.
