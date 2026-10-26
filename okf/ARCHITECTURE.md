---
id: architecture
summary: Components, data flow, threads, input transports, Remote Audio, and how a computer is represented on the phone.
updated: 2026-10-26
sources: [agent/src/server.rs, agent/src/audio.rs, agent/src/main.rs, mobile/lib/connection.dart, mobile/lib/links.dart, mobile/lib/main.dart, mobile/lib/remote_audio.dart, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/RemoteAudio.kt]
---
# Architecture

```
 Phone (Flutter + Android AudioTrack)              Computer (Rust agent, Linux/Windows)
 screens: keyboard / trackpad / mouse(tilt)        accept loop (tokio) + BlueZ service + usb poller
   -> Connection (singleton)                          -> hid::parse -> inject::Input -> uinput/SendInput
      -> Session per computer                         <- leds / levels / focus / info frames
         -> links: WifiLink | BtLink | UsbLink   ==>  Wi-Fi WS :8765 | RFCOMM | WS over `adb reverse`
 RemoteAudio -> source `/audio/v1` WS             <=> PCM capture/playback -> phone or another agent
```
Same binary protocol on all three (see `PROTOCOL.md`). The agent is the only thing that touches the OS.

## Phone side (mobile/lib)
| Piece | Role |
|---|---|
| `Connection` (singleton, `connection.dart`) | all computers; `active` one receives input; coalesces mouse deltas (8 ms flush); remembers held keys/buttons; merge/dedupe of computers |
| Autostart | `autostart.rs`: XDG autostart file written by the agent window (Settings > Start-up) |
| Voice | phone `VoiceController` <-> agent `voice.rs` (0x06 audio up, 0x15 JSON down) <-> Python helper (Whistle, Needle); see FEATURES, AGENT |
| `Session` | one computer: three `Link`s, `preferred` transport, retry with backoff `min(2n,15)s`, `connect(keepTrying)` polls every 4 s when nothing answered at start, `effective` link, per-computer state (leds, volume/brightness/muted, focusTypeable, syncNote) |
| `Link` (`links.dart`) | `WifiLink` (WebSocket), `UsbLink` (= WifiLink to 127.0.0.1), `BtLink` (Kotlin RFCOMM bridge); watchdog + keepalive |
| `Settings` (singleton) | all prefs + saved `Device` list (`settings.dart`) |
| `Home` (`main.dart`) | picks screen by `Mode`; side bar/top bar; auto-keyboard logic; brightness per screen |
| `RemoteAudio` (`remote_audio.dart`) | discovers agent outputs, pins the active computer as source, owns independent source/sink sockets, relays bounded PCM frames to Android or another agent, handles stop/reconnect/errors |
| Kotlin `MainActivity.kt` | channels: `deskctrl/bt` (+events), `deskctrl/window` (cutout, brightness), `deskctrl/link` (+events: deep links), `deskctrl/remote_audio` (`AudioTrack`) |

`effective` link rule: USB if connected, else the user's preferred (Wi-Fi/Bluetooth), else the other. USB use is not a "fallback".
A computer is identified by `computerId` (stable hash of machine-id), else token, else Wi-Fi host:port, else Bluetooth address.

## Agent side (agent/src)
Threads: tokio runtime (WebSocket clients) · BlueZ service thread + one reader thread per Bluetooth phone ·
`leds` (100 ms poll, 1 s heartbeat) · `levels` (400 ms) · `focus` (400 ms window poll + AT-SPI event reader) ·
`usb` (2 s) · bounded Remote Audio capture/playback workers · GUI on the main thread (eframe) or `--headless`. Shared state: `server::Shared` behind a `Mutex`.
Injection: `inject::Input` (tracks held keys, releases them when a phone disconnects).

## Key flows
- **Typing/pointer**: screen -> `Connection.key/move/button/scroll` -> `Session.send` -> `effective` link -> agent `hid::parse` -> uinput.
- **Feedback**: agent pushes `0x10` lock lights, `0x12` volume/brightness, `0x13` typeable focus, `0x11` heartbeat; phone updates `Session` state.
- **USB plug-in**: agent `usb.rs` sees an authorised device -> `adb reverse` + deep link `deskctrl://pair/..?usb=1` -> app `UsbPairing` ->
  `Connection.pairOverUsb` -> UsbLink connects -> agent sends `0x14` info -> phone sets up Wi-Fi/Bluetooth (setting `usbSync`) and merges duplicates.
- **Auto keyboard**: `focus.rs` decides "typeable?" for the front window -> `0x13` -> `Home._textFocus` (modes in `FEATURES.md`).
- **Fail-over**: a link silent > 3.5 s (after heartbeats were seen) is declared dead; traffic moves; held keys are released on the new link.
- **Remote Audio**: the phone opens `/audio/v1` to the active source and optionally another connected destination. Both authenticate with the existing token. The source captures 48 kHz stereo PCM16 into an eight-frame drop queue; the phone strips the 16-byte header for Android `AudioTrack`, or forwards the whole packet unchanged to the destination agent. Input stays on `/`, so audio backpressure cannot delay key-up or pointer frames. Audio uses USB first, then Wi-Fi; Bluetooth-only audio is reported unavailable.
- **Audio route change**: the stream records its source/destination endpoint URLs. A USB/Wi-Fi change either closes both sockets and reports a clear stopped/error state, or reconnects after one second to the same source and destination when the setting is enabled. Destination loss never selects a different output silently.

Remote Audio latency (2026-10-26): capture/playback helpers request 40 ms latency and 10 ms processing instead of server defaults. Android writer uses a short 40/60 ms initial prebuffer, audio thread priority, full partial-write handling (`PcmPump`) and a 4/6-frame bounded queue.
