---
id: decisions
summary: Design decisions with the reason, and the mistakes/gotchas that shaped the rules. Read before changing connection, pairing, auto-keyboard, menus or tests.
updated: 2026-10-25
sources: [mobile/lib/connection.dart, agent/src/usb.rs, agent/src/focus.rs, mobile/lib/edit_menu.dart, mobile/lib/settings_sheet.dart, agent/src/server.rs]
---
# Decisions and lessons (why it is like this)

## Connection / pairing
| Decision | Why |
|---|---|
| USB = `adb reverse` + deep link, UsbLink is the Wi-Fi link to 127.0.0.1 | works on a normal phone (no root), reuses protocol/auth; a plain USB cable cannot make a phone a keyboard without root |
| Agentless options (rooted USB HID gadget, Bluetooth HID, USB board) were discussed, **not built** | needs different stack; see `KNOWN.md` |
| Stable `computerId` (hash of machine-id) | the token changes on every agent restart, so token-matching produced duplicates; id also refreshes a stale token |
| Info frame `0x14` only to loopback clients; phone accepts it only on the USB link | cable = proven physical access; Wi-Fi/BT must not be able to redirect a computer |
| Deep link accepted only with `usb=1` | a stray link may only add a link to the phone's own localhost tunnel |
| Merge precedence: connected entry's token wins, else newer id; merges serialized (`_exclusive`) | a race merged A->B and B->A and deleted both entries |
| `dedupeAll` at start joins only *provable* duplicates | never guess; legacy entries with no host/id stay separate |
| Cable first in `effective`, not a "fallback" | steadiest link; unplugging simply moves traffic |
| Agent tests/demos must not poll USB (`cfg!(test)`, `DESK_NO_USB`) | a test agent paired the user's real phone and overwrote their entry (same computer id) |

## Input / UX
| Decision | Why |
|---|---|
| Auto keyboard decided by the agent (`focus.rs`) with *both* a pull (search focused widget in the front app) and AT-SPI events | window switches often emit no focus event; the first event-only version missed them |
| Report non-typeable (`0x13 0`) too | the phone must know where the focus ended, e.g. after a tab slide |
| 700 ms settle while the window/tab slider is used (`SwitchGuard`) | focus bounces through intermediate tabs/windows |
| Click-only option uses state + click timer (400 ms) and event-after-click (1.5 s) | clicking an already-focused field emits no event |
| Edit menu is one `OverlayEntry` with one `_close()` | a dialog route + barrier closed unreliably; one owner for open/close removes the class of bug |
| Tapped menu stays open, closes after 6 s idle; hold-drag closes on lift | user wants repeated Backspace/Enter taps *and* no manual collapse |
| Hold repeat done by the app (press/release pairs), not by holding the key down | deterministic across OSes, no stuck key if the link drops |
| Fan opens toward the screen middle; closes on rotation | the bar moves to the other side when the phone is turned; a fixed direction ran off-screen |
| Motion cursor = accelerometer tilt joystick, axes from gravity at the moment the finger lands (up = gravity in x/y, right = up x z) | the user's phone has no gyroscope (cheap phones often do not); same feel as the Mouse screen; finger is a clutch by default (no drift) |
| Window/tab slider holds Alt/Ctrl while the finger is down | that is how real Alt+Tab shows the switcher |
| Edge-zone side strips start below the top 25% | keep the top corners free for buttons |
| Surface colours only through `context.desk` (ThemeExtension) | `const` widgets rebuild when the theme changes |
| Agent window: custom-painted icons, Noto Sans if present, exact palette | egui's default font lacks the icons/emoji of the reference design |

## Gotchas that cost time
- `PageStorageKey` on an `ExpansionTile` + a nested `Scrollable` made the scroll read the tile's `bool` as an offset (white screen, endless scroll) - isolate with `PageStorage(bucket: PageStorageBucket())`.
- BlueZ hands over a **non-blocking** socket: set blocking before reading, else every read looks like a bad token.
- Bind the port **first** in `Server::start`; a half-started server made Start a no-op.
- Awaiting `sink.close()` on an unreachable socket hangs "Connecting"; do not await it.
- Changing the layout root rebuilt the Mouse screen and flipped orientation: keep content in a `GlobalKey` subtree.
- `Icons.play_pause` does not exist in this Flutter; sensors_plus events carry micros timestamps; `MockStreamHandler.onListen` must return void.
- `adb shell input text` to a landscape IME covers lower fields: fill one field, `KEYCODE_BACK`, next.
- `grep -c` on a log with NULs prints nothing: `tr -d '\000'` first.
- Never `pkill -f pattern` from the tool shell (matches its own command line and exits the shell).
| Voice: the agent only returns text/intent; the phone maps phrases to actions and types dictation | reuses the phone's action catalog and key frames over every link, no key mapping in Rust, confirmations are phone UI |
| Voice commands: exact phrase table first, Needle only as a guess that is asked about | measured: Needle's confidence is unreliable (wrong "close the tab"->Tab at 0.86); per-action narrow tools improved it but "close window"->close_tab and "volume down"->volume_up still happened |
| Voice recognition on the computer, not on the phone | Whistle/Needle Android libs exist (libneedle.a) but no Dart/Flutter binding and the C API is undocumented; Linux engine is documented |
| Two-finger scroll vs pinch is decided only after BOTH fingers moved (net spread change) | judging after one finger's move made two fingers panning side by side look like a pinch, which would also have hidden the Back / Forward swipe |
| Windows agent from the same code base (cfg split + `#[path]` stubs), built with zig as linker on Linux and tested under Wine | no Windows PC here; keeps one protocol / one set of tests; rustc's mingw link line needs zig's own runtime |
| Windows port owner from `GetExtendedTcpTable`, not `netstat` | netstat's words (LISTENING ...) are translated on non-English Windows |
| Windows keys by virtual-key code through SendInput | follows the PC's keyboard layout (a US-layout scancode table would not) |
| Notch bar is automatic ('auto') and the app always draws into the notch area unless 'off' | Android only reports the notch (display features) when the window may use it; the layout then keeps clear of it by itself (matrix test: 8 hole shapes x portrait / both landscapes / both bars) |
| Window: wgpu first, OpenGL second on Windows | a failed wgpu start (old driver, VM) must not leave the user without a window; measured under Wine/Xvfb |
