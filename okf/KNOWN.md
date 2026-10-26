---
id: known
summary: Limits, unverified items, open problems and ideas. Update when something is fixed or discovered.
updated: 2026-10-26
sources: []
---
# Known limits and open items

## Limits
- Agent supports Linux and Windows. Windows lacks Bluetooth transport, voice, auto-keyboard focus detection, and volume/brightness reporting; see AGENT.md. macOS is not supported.
- Window detection (`xprop`) is X11 only; on Wayland only the AT-SPI path works. Browsers may expose focus only after accessibility has been on a while.
- No agentless mode: a computer without the agent (friend's laptop, login screen, new PC) cannot be used. Options discussed: Bluetooth HID (no root), rooted USB HID gadget, a small USB board (Pico W/ESP32).
- USB needs adb on the computer + USB debugging on the phone (one-time Allow).
- Old agents lack: heartbeat, lock lights (<v2), levels `0x12`, focus `0x13`, info `0x14`; the app degrades gracefully.
- Terminal copy/paste = Ctrl+Shift+C/V (Linux terminals); plain Copy in a terminal sends SIGINT.
- Remote Audio is Wi-Fi/USB only. Bluetooth-only connections remain available for input but cannot carry the raw 1.54 Mbit/s stream.
- Remote Audio v1 is uncompressed 48 kHz stereo PCM16. This favors simple low-latency local playback but uses more bandwidth than Opus; A/V synchronization is best effort and the packet timestamp is not yet used for clock correction.
- Windows Remote Audio cannot mute/reroute the source endpoint safely yet. It starts only when **Also play on source** is explicitly enabled, so duplicate source/destination playback is visible and opt-in.

## Unverified on a real phone / computer
- Motion cursor (`MotionCursor`): accelerometer tilt joystick (the test phone has NO gyroscope, which is why the old gyro version never worked). Only roll/pitch exist, no yaw (turning the phone flat does nothing). Feel not yet judged on the real phone; speed slider is the tuning knob.
- Bluetooth auto-setup from USB (`bt=` in the info frame) tested with a fake bridge only.
- Auto keyboard in Chromium/Brave tab landings (Firefox verified).
- Remote Audio on real hardware: Android phone playback, Linux capture/routing, Windows WASAPI loopback, output hot-unplug, and computer-to-computer playback are implemented but not yet listened to end to end. The dev shell had no active PulseAudio/PipeWire user server, and Wine cannot validate a physical Windows endpoint.

## Open / cleanup
- Legacy duplicate entries on the user's phone ("test" with wrong token, USB only) remain until their agent sends the info frame (needs a restart with the newest agent + one plug-in).
- Two agents on one computer share a `computerId` -> the phone treats them as one computer (by design; avoid in tests).
- `UsbPhone.serial` is only shown in a tooltip.

## Ideas not built
Agentless Bluetooth HID mode; send phone name to the agent for the device table; Opus audio codec/adaptive jitter buffer and timestamp-based A/V clock correction; iOS app.

- Once-paired phones reconnect without manual steps only while the agent's token is unchanged (kept in ~/.config/deskctrl/token). A new Wi-Fi IP address of the computer is still NOT followed (no discovery yet): Bluetooth/USB links cover it, or re-pair.

## Voice control proof of concept (2026-10-17; scripts in tools/voice_poc, zip in output/voice_poc.zip)
- Whistle (speech->text, cactus-needle 3.2.4, Apache-2.0): fast on a modern CPU (14-30 ms for commands), 1.6-4 s on a 2012 AMD A4. Single-word / clipped commands are misheard ("copy"->"Happy", "close"->"Flose"); `keywords=[...]` fixes some (refresh, undo, copy), not all.
- Needle 3 (text->tool call): right action in 11 of 16 command queries; confidence is NOT reliable (wrong "close the tab"->Tab at 0.86, false "tell me a joke"->close_tab at 0.15). Use an exact phrase/synonym table first; Needle only as fallback, with confirmation, narrow per-action tools.
- Android: libneedle.a for android-arm64 (2.2 MB), armv7, riscv64 is published; no Flutter/Dart binding (needs NDK + dart:ffi or Kotlin JNI). The package reports usage unless NEEDLE_TELEMETRY=0.
- Running Needle with all cores froze the dev machine once; run.sh limits threads/memory/time.
- Voice (built 2026-10-17): NOT done: running the engine on the phone itself (phase 5). Not verified on the real phone: the microphone (Mic.kt), permission prompt, real speech through the whole chain. Over Bluetooth the answer can take up to 1 s longer (written when the agent's read loop wakes). Dictation types with a US layout (other layouts get wrong characters). Needle takes 4-13 s per guess on a 2012 CPU. The voice answer applies to the active computer only.
- Voice "RuntimeError: needle_load failed" (2026-10-17): a model download cut off (the dev machine froze during it) left an EMPTY `~/.cache/cactus-needle/v3/<ver>/needle3.cact`, which the Python package trusts forever. `voice_helper.py` now deletes `.cact` files under 1 MB before every use (`heal_cache`), so the package downloads them again. The freeze was not Needle itself: with threads limited it answers in 120-180 ms on that machine.
- Needle froze the dev machine TWICE (2026-10-17, power-off needed; the second time during a 23-query test with ~60 tools, helper under nice + ulimit -v 8G + 1 thread). Not memory: on the SSH box the helper stays at ~114 MB peak and answers 60-tool queries fine. Cause NOT found, nothing was run here after the second freeze. Mitigations: `voiceAi` off by default, systemd scope limits, 2 cores. Do not re-test on the dev machine without the owner's OK (memory note never-run-needle-locally).
- Voice "no response" (2026-10-17): the agent's own safety limits (CPUQuota=150% + 2-core affinity) starved the Needle/Whistle engine, which runs one busy-waiting thread per core: the helper burned 4+ minutes of CPU on a 3 s clip (cgroup throttled 99% of periods). Fixed by dropping the quota/affinity and using the idle scheduling class instead (test: `the_helper_is_started_with_limits_but_never_with_fewer_cores`). The phone now shows "Still working - the computer is slow or loading the model..." after 10 s and gives up after 200 s. The engine's one-spinning-thread-per-core pool is also the best guess for the two dev-machine freezes (nothing proven).
- Windows agent (built 2026-10-18, only run under Wine): NOT verified on a real Windows PC: SendInput into real programs, the Windows Firewall prompt, USB with adb.exe, autostart after a real login, Run-key value, window drawing with real GPU drivers (wgpu then OpenGL fallback), the `LockWorkStation` key. Missing on Windows: Bluetooth, volume / brightness percentages, brightness keys, auto-keyboard (UI Automation), Voice. Phone shortcuts written for Linux (Open terminal Ctrl+Alt+T, Super for overview, Print Screen) may differ on Windows. The exe is unsigned (SmartScreen warns). Relative mouse movement goes through Windows pointer acceleration.
- Notch bar (2026-10-19): arranged and tested for 8 camera-hole shapes (centre / corner punch holes, waterdrop, wide, very wide) in dp; NOT seen on a real second phone. On a phone where Android reports no cutout even with `shortEdges`, 'auto' behaves like 'off' (use 'On'). Android < 9 has no cutout API.
- Flaky: the agent's port tests (`free_port()` race) fail now and then and pass on a rerun.
- Round-menu Copy / Paste "not working" (reported 2026-10-18, both normal and terminal, Linux, maybe Windows): phone frames (Ctrl+C = 1,0,224 / 1,0,6 ...) and the Linux agent's uinput events (29, 46 ...) were read back and are correct. A Tk test window that held the X focus received Ctrl+V once but later chords reached nothing (stray Alt_L from another source moved the focus), so the test was inconclusive; NOT resolved, investigation interrupted by the owner.

- Remote Audio stutter reported on hardware (2026-10-26): capture batching and Android empty-buffer startup addressed with explicit Pulse timing, short native prebuffer and partial-write handling. No exact end-to-end latency or lip-sync guarantee; listen again using both updated APK and agent.

- Trackpad now-playing reporting (2026-10-26) currently uses Linux MPRIS. Players that disable or omit MPRIS metadata cannot provide a title. PNG-installed app icons are supported; SVG-only/missing icons use a music-note fallback. Windows and Android local-phone media metadata remain unsupported (no stale desktop title is shown in phone mode).

- Playback timeline uses Linux MPRIS capabilities. Position and CanSeek are needed for seeking; missing length disables only the percentage timeline, not forward/backward. Unknown duration is shown as --:-- (it is not proof of a live stream). Windows and Android local-phone media remain unsupported. The timeline updates from one-second source samples with local interpolation, so network/player delays can briefly differ from the desktop's displayed clock.

Audio interruption recovery (2026-10-26): opt-in auto-reconnect now covers unexpected audio WebSocket/source/sink loss, not only transport changes; working routes are pinned and sockets use Ping liveness. A three-minute fake-agent PCM relay with three deliberate drops passed. This verifies transport recovery, not uninterrupted real-speaker playback or exact A/V timing.

Playback timing dropout fix: last valid duration is retained per identified video when Firefox temporarily omits timing after a seek. This cannot invent a total for media that never supplies one. Install updated APK and reopen rebuilt Linux agent to use URL-based, duration-independent seek fingerprints. Actual phone reproduction and post-fix checks used a recording test source; real Firefox control input was not injected.
