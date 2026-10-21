---
id: operations
summary: Build, install, publish and run commands; paths; adb tricks; the laptop setup script.
updated: 2026-10-21
sources: [output/setup_laptop.sh, mobile/pubspec.yaml, agent/Cargo.toml]
---
# Operations

Branding is ViL / ViL Agent. `python3 tools/prepare_branding.py` regenerates launcher assets from the approved master in `branding/`. Ship `output/vil-icon.png` alongside the Linux installer; it installs the icon into hicolor and sets the launcher name to ViL Agent. Windows GNU builds require `x86_64-w64-mingw32-windres` (`WINDRES` override) for the executable icon. Output binary/APK filenames keep their existing DeskCtrl names.

## Toolchain
Flutter at `~/dev/flutter`, Android SDK `~/dev/android-sdk`: `export PATH=$HOME/dev/flutter/bin:$PATH ANDROID_HOME=$HOME/dev/android-sdk`. Rust stable (edition 2024). Python 3 (PIL, gi/Atspi, websockets 10 present).

## Build / ship (phone)
```
cd mobile && dart format lib test && flutter analyze && flutter test
flutter build apk --release && cp build/app/outputs/flutter-apk/app-release.apk ../output/desk_ctrl.apk
timeout 120 adb install -r ../output/desk_ctrl.apk        # keeps settings + computers
```
Standing rule: do this after **every** phone change (memory `auto-install-apk`). No phone attached -> say so, leave the APK in `output/`, give the user: `adb install -r /home/sam/Desktop/project/desk_ctrl/output/desk_ctrl.apk` (or copy the APK to the phone).

## Build / ship (agent)
```
cd agent && cargo test && cargo build --release          # binary: target/release/agent
cp target/release/agent ../output/desk_ctrl_agent.new && mv ../output/desk_ctrl_agent.new ../output/desk_ctrl_agent   # the old file may be running ("Text file busy")
```
The user restarts their own agent to pick it up; installing = copying `output/desk_ctrl_agent` (+ `setup_laptop.sh`) to each computer.

## setup_laptop.sh (needs sudo, user runs it)
Installs udev rule `99-deskctrl-uinput.rules` (uaccess + group input), loads `uinput`, installs `adb` + `android-sdk-platform-tools-common` (apt), copies the agent to `/usr/local/bin/desk_ctrl_agent`, adds a desktop launcher. Steps numbered 1/4..4/4.

## adb cheat sheet
- `adb reverse --list` (tunnels; the user's agent normally has `tcp:8765`), `adb reverse --remove tcp:PORT` (clean test tunnels).
- `adb reconnect` makes the phone look unplugged+replugged -> the user's agent re-pairs it (repairs an entry a test agent overwrote).
- `adb exec-out screencap -p > x.png`, `adb shell dumpsys window | grep mCurrentFocus` (is the app in front?), `adb shell input tap|swipe|text|keyevent`.
- Ports: user's real agent 8765. Test agents: 8790-8794 with `DESK_NO_USB=1`. Phone Wi-Fi 172.22.36.x, laptop 172.22.36.165 / 10.63.x (routable).

## Misc
`tools/gen_sounds.py` generates the key click sounds (assets). Reference design image for the agent window: `agent_ui.png` (project root).
Hostname of the dev laptop is `test` (so USB-paired computers show as "test").

## setup_voice.sh (voice engine, user runs it on the computer, no sudo)
`output/setup_voice.sh` + `output/voice_helper.py` (sources: `agent/voice/`). Creates `~/.local/share/deskctrl/voice/env` (uv or python3-venv), installs `cactus-needle>=3.2`, downloads Whistle + Needle 3 (~25-50 MB) into `~/.cache/cactus-needle`, then restart the agent. Telemetry of the package is switched off by the agent / script. Proof of concept kit: `output/voice_poc.zip` (`tools/voice_poc`).

## Windows agent (built on Linux)
`tools/windows/build_windows.sh` builds `output/desk_ctrl_agent.exe` (target `x86_64-pc-windows-gnu`, linker = zig through `tools/windows/zigcc.py`, which drops the mingw libs rustc asks for, adds `-lunwind` and turns `-lwindows.X` into the import libs of the windows crates; zig comes from `uv pip install ziglang` in `~/winbuild/zigenv`, no sudo). `./tools/windows/build_windows.sh test` runs the agent tests of the Windows build under Wine (`~/.wine-deskctrl`). The build needs ~3 GB in `~/winbuild/target`: delete it afterwards (the disk of this machine is nearly full). Ship `output/desk_ctrl_agent.exe` + `README_windows.txt` + `allow_firewall.bat`.
