---
id: index
summary: Start here. What DeskCtrl is, where things are, which file to read for which task, the update rules.
updated: 2026-10-26
sources: []
---
# DeskCtrl - OKF index (read this first; then read only what the task needs)

**What it is**: the phone (Flutter, Android) becomes keyboard + trackpad + mouse and a remote audio output for Linux or Windows computers.
A desktop **agent** (Rust) receives input over **Wi-Fi** (WebSocket), **Bluetooth** (Linux RFCOMM) or a **USB cable**
(adb reverse tunnel), then injects it through `/dev/uinput` or Windows `SendInput`. Remote Audio uses a separate authenticated WebSocket over Wi-Fi/USB. Input links fail over automatically.

**Layout**: `README.md` quick start and usage guide · `agent/` Rust agent + window · `mobile/` Flutter app · `output/` built `desk_ctrl.apk`,
`desk_ctrl_agent` (Linux), `desk_ctrl_agent.exe` (Windows), `setup_laptop.sh` · `tools/` helper scripts · `okf/` this knowledge base.

**Brand**: display names are ViL (phone) and ViL Agent (desktop). Approved artwork and generated icon files live in `branding/`; regenerate with `tools/prepare_branding.py`. Internal package/config/pairing identifiers and output filenames retain DeskCtrl for upgrade compatibility.

**State now**: phone tests 259, agent tests 80 on Linux (32 run the Windows build under Wine), all passing. Newest changes: `LATEST.md` (read it second, it is short).

## Which file for which task
| Task | Read |
|---|---|
| What changed lately / where did we stop | `LATEST.md` (then `CHANGELOG.md` only for older history) |
| Understand the whole design, data flow, threads | `ARCHITECTURE.md` |
| Touch the wire format, links, fail-over, key codes | `PROTOCOL.md` |
| Change the Rust agent or its window | `AGENT.md` |
| Change the Flutter app (screens, gestures, menus) | `MOBILE.md` |
| Add / change a setting | `SETTINGS.md` (keys, defaults, where used) |
| "Does it already do X?" / user-visible behaviour | `FEATURES.md` |
| Run / write tests, test on the real phone safely | `TESTING.md` |
| Build, install, publish, adb, setup script | `OPERATIONS.md` |
| Why was it built this way, past mistakes | `DECISIONS.md` |
| Limits, open problems, ideas | `KNOWN.md` |
| How OKF itself works / how to update it | `OKF.md` |

## Commands you will need most
```
export PATH=$HOME/dev/flutter/bin:$PATH ANDROID_HOME=$HOME/dev/android-sdk
cd mobile && flutter analyze && flutter test            # phone side
cd agent  && cargo test && cargo build --release          # agent side
python3 okf/okf.py check                                  # validate this knowledge base
```
Build/install/publish details: `OPERATIONS.md`.

## Non-negotiable rules (learned the hard way, details in `DECISIONS.md`)
1. After **every** change: `python3 okf/okf.py log "title" -d DOC,DOC -f files -t "tests"` (see `OKF.md`).
2. After every phone change: run tests, build the APK, copy to `output/desk_ctrl.apk`, `adb install -r` it.
3. Never send test input to a real computer. Use a recording fake agent on a spare port (`TESTING.md`).
4. Never `pkill -f <pattern>` (kills your own shell); take PIDs from `ss -ltnp` / `ps`.
5. Never start a second real agent next to the user's with USB auto-connect on: the phone merges them (same computer id).
   Use `DESK_NO_USB=1` for demos.
6. Check the phone screen (screenshot) before tapping it; a tap on the keyboard screen types on the active computer.
