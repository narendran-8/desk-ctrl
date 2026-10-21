---
id: protocol
summary: Wire format phone<->agent for all transports, key code space, liveness and fail-over rules, USB pairing link, framing.
updated: 2026-10-18
sources: [agent/src/hid.rs, agent/src/server.rs, agent/src/bluetooth.rs, agent/src/identity.rs, agent/src/levels.rs, agent/src/focus.rs, agent/src/leds.rs, mobile/lib/links.dart]
---
# Protocol (binary, big-endian)

## Phone -> agent
| Byte 0 | Payload | Meaning |
|---|---|---|
| `0x00` | - | keep-alive (every ~1 s). Agent enforces a 5 s timeout only for phones that ever sent one (old apps never time out) |
| `0x01` / `0x02` | u16 hid | key down / key up |
| `0x03` | i16 dx, i16 dy | pointer move (relative px) |
| `0x04` | u8 button (0 L,1 R,2 M), u8 down | mouse button |
| `0x05` | i16 dx, i16 dy | scroll |
| `0x06` | u8 op, ... | **voice** (voice.rs): op 1 begin [u8 mode: 0 dictate, 1 command], 2 audio (16 kHz mono i16 LE, <= 250 bytes/frame so it fits Bluetooth), 3 end (recognise), 4 cancel, 5 intent request (UTF-8 text) |

Key codes: USB HID keyboard usage (< 0x100, e.g. Enter 0x28, Backspace 0x2A, Tab 0x2B, Delete 0x4C, arrows 0x4F-0x52,
Print Screen 0x46, modifiers 0xE0-0xE7). Media/system keys = `0x8000 | consumer usage`:
vol up `0x80E9`, vol down `0x80EA`, mute `0x80E2`, brightness up `0x806F` / down `0x8070`, next `0x80B5`, previous `0x80B6`,
play/pause `0x80CD`, calculator `0x8192`, lock `0x819E`, mic mute `0x8F01` (no usage). Mapping to evdev: `hid::hid_to_evdev`.

## Agent -> phone
| Frame | Meaning |
|---|---|
| text `ok` | token accepted (Wi-Fi; first message). Bluetooth: byte `0x06` (ACK) |
| `0x10 flags` | lock lights: bit0 Caps, bit1 Num, bit2 Scroll (from `/sys/class/leds`) |
| `0x11` | heartbeat, every 1 s, also right after the accept. Phone treats any traffic as life |
| `0x12 vol brightness muted` | percentages; `0xFF` = unknown (agent sends only after it read something; `NOTHING=[0xFE,0xFE,0]` is internal) |
| `0x13 [typeable]` | focus landed on something typeable (1) / not (0). Old agents send just `0x13` = 1 |
| `0x15 last json...` | voice answer in pieces of <= 248 bytes (`last` = 1 on the final piece); the joined bytes are JSON: `{t:text,text}`, `{t:intent,calls:[{name}],confidence}`, `{t:unavailable,msg}`, `{t:error,msg}`. Bluetooth: written when the agent's read loop wakes (the phone's keep-alive, <= 1 s) |
| `0x14 text` | **USB link only** (client address is loopback): `id=<computerId>&port=<n>&name=<host>&ip=<lan ip>&bt=<mac>` |

## Transports
- **Pairing token**: kept by the agent in `~/.config/deskctrl/token` across restarts (16 hex chars), see AGENT.md.
- **Wi-Fi**: WebSocket `ws://host:8765` (`DESK_PORT`). First frame = token (text). Wrong token: 800 ms delay, close.
- **Bluetooth**: RFCOMM service UUID `c0de5c71-7e1a-4d1c-8d5e-d35c7c71a001`, fixed channel 22-30 + explicit SDP record (BlueZ `Profile1`).
  Framing `[len][payload]`; first frame is the token; the phone's Kotlin bridge keeps one socket per computer.
- **USB**: the Wi-Fi protocol through `adb reverse tcp:P tcp:P`; the phone connects to `127.0.0.1:P` (`UsbLink`). Agent knows a loopback peer = USB.

## Liveness & fail-over
- Phone: watchdog tick 500 ms; keep-alive every 2nd tick; link dead after `Link.deadAfter` = 3.5 s without any frame **once a heartbeat was seen**.
- Agent: `CLIENT_TIMEOUT` 5 s (1 s in tests) for phones that sent a keep-alive.
- Session: effective link = USB if up, else preferred, else other. On a switch the held keys/buttons are released on the new link.
- Retry: disconnected-but-wanted link retried after `min(2*attempt, 15)` s.

## USB pairing link (phone entry point, `AndroidManifest.xml` intent filter `deskctrl://pair`)
`deskctrl://pair/<token>?usb=1&port=<n>&name=<host>&id=<computerId>` (sent by `adb shell am start -a VIEW -p com.deskctrl.deskctrl -d '<uri>'`).
The app **ignores** links without `usb=1`; they only add a link to 127.0.0.1. QR codes use `deskctrl://pair/<token>?port=&id=&ip=&bt=`.
