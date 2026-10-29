---
id: settings
summary: Every saved setting - key, default, meaning, where it is used - plus the Device record and where each switch appears in the settings sheet.
updated: 2026-10-29
sources: [mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/lib/remote_audio.dart]
---
# Settings (`Settings` singleton, SharedPreferences keys)

Desktop agent setting (separate from phone preferences): Settings > Window > Minimize to tray, default off. Saved as `minimize-to-tray` in the agent configuration directory. See AGENT.md.

Change with `Settings.instance.update(() => s.x = v)`. UI: `settings_sheet.dart` (sections below). Scoped sheets: keyboard / touchpad / mouse show only their sections + an "All settings" button.

## General / display
| Key | Default | Meaning | Section |
|---|---|---|---|
| `notchBar` | 'auto' | 'auto' = a phone WITH a camera notch gets the icon bar around it, one without keeps the top bar; 'on' = always the icon bar; 'off' = never (and the app does not draw into the notch area). Old `sideBar` true is read as 'on'. `Settings.sideBar` is still a bool view of it ('on') | General (Auto / On / Off) |
| `haptic` | true | vibration feedback | General |
| `autoReconnect` | true | reconnect the last connected computers at start | General |
| `usbSync` | true | over USB, also set up Wi-Fi + Bluetooth for that computer | General |
| `theme` | `soft` | `soft` / `amoled` (true black) / `tinted` ("Black lite") | Appearance |
| `accent` | 0xFF4F8CFF | accent colour (8 swatches) | Appearance |
| `brightKeyboard` `brightPad` `brightMouse` | 0 | phone screen brightness per screen, 0 = system, else 0.1-1.0 | Screen brightness |
| `modeOrder`, `mouseTab`, `padTab`, `voiceTab`, `mobileTab` | keyboard,mouse,pad,voice,mobile; true | order and availability of screens; keyboard is always enabled; old saved orders append newly added modes | Screens |
| `editMenu` | true | corner button with the edit fan | General + Keyboard |
| `editMenuStayOpen` | true | a tapped fan stays open after an option (idle close 6 s) | General + Keyboard |
| `copyOnSelect` | true | a left-button drag (>=24 px) or double/triple click, once released, sends Ctrl+Insert after 100 ms and shows a "Copied" toast | General + Trackpad |
| `editCustom` | '' | the user's own menu keys as JSON `[{id: custom_N, label, mods (1 Ctrl,2 Shift,4 Alt,8 Super), key (HID, or 0x8000|consumer), repeats}]`; invalid entries are dropped on read | General (EditMenuEditor) |
| `editLayout` | '' | rows of option ids, rows ';' ids ',' ('' = standard rows); `decodeEditLayout` drops unknown ids, max 3 rows x 6 | General (EditMenuEditor) |
| `editMenuHoldRepeat` | true | holding Backspace/Delete/Enter/Tab/Page keys repeats | General |
| `editMenuIdleSeconds` | 6 | idle seconds before an open fan folds (2-30) | General |

## Remote Audio Output
| Key | Default | Meaning |
|---|---|---|
| `remoteAudioEnabled` | true | shows the speaker button and permits Remote Audio discovery/streaming; turning it off stops an active stream |
| `remoteAudioAutoReconnect` | false | after a stream/socket or USB/Wi-Fi endpoint loss, retry the same source and selected output after 1/2/4/8 seconds (capped); Stop cancels retries, off stops with a clear message. Also exposed in Audio Output panel |
| `remoteAudioPlaySource` | false | computer capture only: also leave playback audible at the source; Linux off uses a temporary null sink, while Windows currently requires this to be true |
| `remoteAudioLatency` | `balanced` | `low` = 40 ms prebuffer / 4 queued frames, `balanced` = 60 ms prebuffer / 6 queued frames; invalid saved values reset to balanced |
| `remoteAudioPlayPhone` | false | phone capture only: off silences phone media volume while forwarding audio to the computer; on plays both. Live switch in Audio Output and Settings. Saved media volume restored on Stop/error/revocation; interrupted-process recovery on app launch |
| `remoteAudioSource` | `computer` | `computer` = existing desktop capture; `phone` = Android10+ permitted playback sent to a connected computer output; cannot change while running |
| `remoteAudioLastDestination` | `phone` | `phone` or `<deviceId>|<outputId>`; used only if discovery confirms it still exists, otherwise first valid destination (phone for computer source, first computer output for phone source) |

## Keyboard
| Key | Default | Meaning |
|---|---|---|
| `fnRow` | true | show F1-F12 row |
| `fnKey` | true | Fn key (brightness/volume/media on the F-row); needs `fnRow` |
| `joinDelete` | false | Backspace and Del on one key (swipe to switch) |
| `sound` | true | key click sound; `pack` (`mechanical`/`soft`/`typewriter`, "silent" = sound off); `volume` 0.8 |
| `autoKeyboard` | true | switch to the keyboard when the computer's focus lands on a typeable field |
| `autoKeyboardOnClick` | false | ...but only right after you click with the pointer (focus moving by itself never opens it) |

## Touchpad
| Key | Default | Meaning |
|---|---|---|
| `padEnabled` | true | the pad reacts to touches |
| `padPhoneMediaButton` | true | show the Mobile media toggle on the Trackpad and combined Mobile screens; local media mode starts off and routes edge media actions to Android when toggled on |
| `pointerSpeed` | 1.5 | finger pointer speed (0.5-4) |
| `tapToClick`, `naturalScroll` | true, true | taps click; scroll direction |
| `padButtons` | true | slim Left/Right bar under the pad |
| `screenshotSwipe` | true | 3-finger swipe down = Print Screen |
| `padZones` | true | edge controls master switch (left volume, right brightness, top media, bottom windows) |
| `padTopMode` | `seek` | top edge slide: `seek` (Left/Right arrows) or `track` (next/previous track) |
| `seekSpeed` | 3 | 1-5; hold repeat 120 ms / factor (0.4,0.7,1,1.6,2.5), slide step 60 px / factor |
| `padWindows` | true | bottom strip switches windows (Alt+Tab) |
| `padTabSwitch`, `switchTabs` | true, false | bottom strip centre icon toggles windows <-> browser tabs (Ctrl+Tab); `switchTabs` = current mode |
| `padSwipeNav` | true | two-finger sideways swipe = Back / Forward (Alt+Left / Alt+Right); sideways scrolling off while on | Touchpad |
| `padMotion` | false | phone motion moves the cursor (air mouse) |
| `padMotionSpeed` | 900 | 200-2500, 900 = normal (same scale as the Mouse screen's `gyroSpeed`) |
| `padMotionAlways` | false | motion works without a finger on the pad; a finger adds to it |
| `padMotionInvert` | false | invert motion direction |

## Tilt mouse screen
`gyroSpeed` (900, 200-2500) tilt speed, `invertGyro` (false).

## Computers (JSON in `devices`, plus `lastConnected` list, `lastActiveId`)
`Device`: `id` (time in microseconds as text), `name`, `host`, `port` (8765), `token`, `useWifi` (true), `useBt`, `btAddress`, `btName`,
`useUsb` (cable link, host fixed 127.0.0.1), `transport` (`wifi`|`bluetooth`, the user's preferred non-cable link), `computerId` ('' until known).
`Settings.findSame(d)`: same `computerId`, same `token`, same `host:port`, or same Bluetooth address (case-insensitive) = same computer.

## Voice (`Mode.voice`, Settings > Voice)
| Key | Default | Meaning |
|---|---|---|
| `voiceTab` | true | the Voice screen is one of the modes |
| `voiceHold` | true | hold the button to talk (off: tap to start, tap to stop) |
| `voiceAi` | false | unknown commands are guessed by Needle on the computer, always asked first |
| `voiceEnter` | false | press Enter after dictated text |
| `voiceSpace` | true | a space after dictated text |
| `voiceConfirmRisky` | true | ask "Run it?" before closing a window (Alt+F4) |

## Mobile combined screen
`mobileTab` (default true) shows a fifth mode with touchpad above the keyboard. Its in-screen swap button reverses or restores those sections for the current Mobile screen instance; this order is not a saved setting. Portrait uses Mobile's own six-row compact keyboard, including a punctuation row; no setting changes the normal Keyboard mode layout. It uses `padEnabled`, the existing touchpad gestures and edge controls, and the normal keyboard settings. The scoped Mobile settings sheet shows both Keyboard and Touchpad sections. `brightPad` is also used for this screen.
