---
id: protocol
summary: Input and Remote Audio wire formats, key code space, liveness/fail-over rules, USB pairing link, and framing.
updated: 2026-10-26
sources: [agent/src/hid.rs, agent/src/server.rs, agent/src/audio.rs, agent/src/bluetooth.rs, agent/src/identity.rs, agent/src/levels.rs, agent/src/focus.rs, agent/src/leds.rs, mobile/lib/links.dart, mobile/lib/remote_audio.dart, agent/src/media.rs, mobile/lib/now_playing.dart]
---
# Input/control protocol (binary, big-endian)

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

## Remote Audio protocol (`/audio/v1`)

Remote Audio is an independent WebSocket on the same agent port. The HTTP path is `/audio/v1`; the first frame is the same pairing token as text, and the agent answers text `ok`. Existing input clients remain on `/`, so no existing frame meaning changes. This service is available through Wi-Fi or the USB reverse tunnel; it does not use RFCOMM.

The next client text frame is one JSON operation:

| Operation | Fields | Agent response / behavior |
|---|---|---|
| `discover` | none | `devices`: protocol `version`, `computerId`, `name`, capture availability, `outputs:[{id,label}]`; then the short discovery socket closes |
| `source` | `playSource` boolean | `active` with role/source/rate/channels, then binary audio packets until `stop` or disconnect |
| `sink` | exact output `device` id | `active` with role/sink/device, then accepts binary audio and `gain` |
| `gain` | `volume` 0..1, `muted` boolean | changes this remote stream only |
| `stop` | none | closes capture/playback and restores any temporary Linux routing |

Errors are text JSON `{"op":"error","version":1,"message":"..."}`. The phone never falls through to another output after an error.

Each binary packet is one 20 ms PCM frame:

| Bytes | Encoding |
|---|---|
| 0 | data type `1` |
| 1 | audio protocol version `1` |
| 2 | channels `2` |
| 3 | sample format `1` = signed PCM16 little-endian |
| 4..7 | sample rate `48000`, u32 little-endian |
| 8..11 | sequence, u32 little-endian |
| 12..15 | source Unix timestamp milliseconds modulo 2^32, u32 little-endian |
| 16..3855 | 960 stereo sample frames = 3840 PCM bytes |

Raw payload is 192 kB/s, about 1.536 Mbit/s before WebSocket overhead. Queues are bounded and discard old/full frames rather than delaying input. The timestamp is carried for future clock correction; current A/V synchronization is best effort.

## Liveness & fail-over
- Phone: watchdog tick 500 ms; keep-alive every 2nd tick; link dead after `Link.deadAfter` = 3.5 s without any frame **once a heartbeat was seen**.
- Agent: `CLIENT_TIMEOUT` 5 s (1 s in tests) for phones that sent a keep-alive.
- Session: effective link = USB if up, else preferred, else other. On a switch the held keys/buttons are released on the new link.
- Retry: disconnected-but-wanted link retried after `min(2*attempt, 15)` s.

## USB pairing link (phone entry point, `AndroidManifest.xml` intent filter `deskctrl://pair`)
`deskctrl://pair/<token>?usb=1&port=<n>&name=<host>&id=<computerId>` (sent by `adb shell am start -a VIEW -p com.deskctrl.deskctrl -d '<uri>'`).
The app **ignores** links without `usb=1`; they only add a link to 127.0.0.1. QR codes use `deskctrl://pair/<token>?port=&id=&ip=&bt=`.

Timing (2026-10-26): packet format unchanged. Pulse capture/playback requests 40 ms latency and 10 ms processing. Android starts after 40/60 ms prebuffer (Low/Balanced) with 4/6 application frames, instead of starting empty with 8/20 frames. These are buffering targets, not measured end-to-end latency.

## Now-playing feedback (`0x16`)
Agent -> phone, over all existing input transports: `[0x16, flags, ...UTF-8 JSON chunk]`. `flags & 1` begins a fresh message, `flags & 2` ends it; a one-frame message uses `3`. Payload chunks are <=240 bytes, so total frames are <=242 bytes and fit RFCOMM. Joined JSON is `{title, app, playing, icon}`; `icon` is base64 PNG of the installed source-app icon (24px), never album art. `{}` clears the current media. Each Link assembles its own bounded 24KB message before Session updates; UTF-8 is decoded only after joining. Wi-Fi event broadcast capacity is 256 frames so one icon update fits without displacing its own chunks. Old apps ignore this new frame; existing frame meanings are unchanged. Reports repeat every four seconds and update on a one-second poll when changed.
