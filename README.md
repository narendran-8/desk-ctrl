# ViL

ViL turns an Android phone into a wireless keyboard, trackpad, mouse, voice controller, and remote audio output for a computer.

The project has two parts:

- **ViL mobile app** — a Flutter Android app with keyboard, trackpad, mouse, voice, gestures, shortcuts, a customisable round action button, and computer-audio playback.
- **ViL Agent** — a Rust desktop program that receives phone input, sends keyboard and mouse events to the operating system, and captures or plays Remote Audio.

The phone and computer can communicate over Wi-Fi, Bluetooth, or a USB cable. The app remembers paired computers and automatically changes to another available connection when the current connection fails.

## Supported systems

| Part | Supported system |
| --- | --- |
| Mobile app | Android  |
| Desktop agent | Linux (full support) |
| Desktop agent | Windows (Wi-Fi and USB support; see limitations below) |

The desktop agent is not an iOS application. The Flutter project currently builds the Android app.

## Project layout

```text
mobile/                 Flutter Android application
agent/                  Rust desktop agent
branding/               ViL icons and branding source files
output/                 Local build and installation helpers
tools/                  Build and test utilities
okf/                    Detailed project knowledge base
back_dir/memory/        Project memory notes
```

The internal package name, pairing identifiers, and output filenames still use `deskctrl` for upgrade compatibility. The user-facing name is **ViL** and the desktop name is **ViL Agent**.

## Quick start for a Linux computer

### 1. Build the desktop agent

Install Rust, then build the agent:

```bash
cd agent
cargo test
cargo build --release
cp target/release/agent ../output/desk_ctrl_agent
cd ..
```

The agent needs access to Linux `/dev/uinput` so it can create a virtual keyboard and mouse. The easiest setup is to place `output/desk_ctrl_agent`, `output/setup_laptop.sh`, and `output/vil-icon.png` in one folder and run:

```bash
cd output
sudo ./setup_laptop.sh
```

The setup script installs the uinput permission rule, USB support when `adb` is available, PulseAudio client tools for Remote Audio, the agent, and a **ViL Agent** launcher. Log out and back in if Linux asks you to refresh the `input` group permission.

For a development run without installing the agent:

```bash
cd agent
cargo run --release
```

The normal Wi-Fi port is `8765`. To run without the GUI, use `--headless`:

```bash
DESK_NO_USB=1 cargo run --release -- --headless
```

Do not run a second agent beside your normal agent with USB auto-connect enabled. Use `DESK_NO_USB=1` for a test or demo copy.

### 2. Build the Android app

Install Flutter and the Android SDK. This project expects Flutter at `~/dev/flutter` and the Android SDK at `~/dev/android-sdk`, but any valid Flutter and Android SDK installation works if the environment variables are adjusted.

```bash
export PATH="$HOME/dev/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/dev/android-sdk"

cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk ../output/desk_ctrl.apk
```

Install the APK on a USB-connected Android phone:

```bash
adb devices
adb install -r ../output/desk_ctrl.apk
```

The `-r` option keeps the app's saved settings and paired computers. If no phone is attached, the APK is still available at `output/desk_ctrl.apk` after the build.

## Pair the phone with the computer

### Wi-Fi

1. Start **ViL Agent** on the computer.
2. Make sure the phone and computer are on the same network.
3. Open ViL on the phone.
4. Scan the QR code shown by the agent, or enter the displayed address, port, and token manually.
5. Select the computer in the phone's computer list.

After the first successful pairing, the agent keeps its token and the phone remembers the computer. When the agent starts again, the app can reconnect automatically.

### USB

1. Enable Android Developer Options and USB debugging.
2. Connect the phone with a USB cable and approve the computer on the phone.
3. Start the agent with `adb` installed.
4. The agent creates an `adb reverse` tunnel and pairs the phone automatically.

The Linux setup script installs `adb` on Debian or Ubuntu when possible. On Windows, place `adb.exe` from Android SDK Platform-Tools in the same folder as `desk_ctrl_agent.exe`.

### Bluetooth

Bluetooth support is available through the Linux agent and BlueZ. Pair the phone with the computer in the operating system first, then start the agent. The app can use Bluetooth as another connection medium and fail over when Wi-Fi or USB is unavailable.

## Use the app

The phone provides these main modes:

- **Keyboard** — type text, use modifier keys, navigation keys, function keys, media keys, and custom keys.
- **Mouse** — use left, right, middle, double-click, drag, and scroll controls.
- **Trackpad** — move the pointer, tap, drag, scroll, zoom, use multi-finger gestures, and optionally control the pointer with phone motion.
- **Voice** — dictate text or hold the command button to speak an action. Voice processing runs locally on the computer after the optional voice setup.
- **Mobile** — a touchpad and keyboard on one screen, so you can point and type without changing modes. Tap the swap icon to place either the touchpad or keyboard on top. Portrait uses a compact keyboard with letters, numbers, modifiers, arrows, and a full punctuation row (`- _ = + [ { ] } ; :` and more); tap the rotate icon on the touchpad to switch orientation. Top-edge play/pause and track buttons control the computer by default; tap the phone icon to control media on Android instead. Show or hide the screen in Settings > Screens.
- **Round action button** — open shortcuts such as copy, paste, terminal actions, refresh, open terminal, close application, and custom keys.

The round button can be edited from the app's Settings. You can add, remove, reorder, and move actions between rows, create custom key actions, choose whether the menu stays open, and configure hold-repeat and idle-close behavior. A row's actions share the row's available arc, so four actions fill the row evenly.

The side connection icon shows the active medium. It changes between Wi-Fi, Bluetooth, and USB during automatic fail-over.

## Remote Audio Output

Remote Audio sends the active computer's desktop/media playback to this Android phone or to a specific output on another connected ViL Agent computer.

1. Connect the source computer and, for computer-to-computer playback, the destination computer.
2. Tap the speaker icon directly above the Keyboard/Trackpad/Mouse mode button.
3. Select **This phone** or one of the named output devices on another computer.
4. Tap **Start**. The panel provides Stop, Mute, and stream Volume controls and shows connecting, active, unavailable, and error states.

The stream stays active while changing ViL modes. Audio uses its own authenticated WebSocket, so it cannot delay keyboard or pointer traffic. USB is preferred when present; Wi-Fi is used otherwise. Bluetooth-only control connections remain usable for input, but Remote Audio requires USB or Wi-Fi. If the route changes, the stream either stops with a message or reconnects to the same destination according to **Settings > Remote Audio Output > Reconnect after a connection change**. It never silently chooses another speaker.

Linux uses the current PulseAudio or PipeWire-Pulse desktop monitor through `pactl`, `parec`, and `pacat`. With **Also play on the source computer** off, ViL temporarily routes playback through a private null sink and restores the previous default/output routes when stopped. Windows uses WASAPI loopback through CPAL. Windows currently requires **Also play on the source computer** to be enabled because the agent cannot yet mute the source endpoint safely.

The first implementation sends 48 kHz stereo PCM16 in 20 ms frames, about 1.54 Mbit/s before WebSocket overhead. It is intended for a local Wi-Fi network or USB connection. Audio is held only in bounded memory queues and is never recorded to disk. Video synchronization is best effort; the packet timestamp is reserved for later clock correction.

## Optional voice control

Voice control is optional and is currently intended for Linux. It uses Cactus Needle and Whistle locally on the computer.

Copy `output/setup_voice.sh` and `output/voice_helper.py` to the computer where the agent runs, then execute:

```bash
cd /path/to/voice-files
./setup_voice.sh
```

The script creates a private environment under `~/.local/share/deskctrl/voice`, installs `cactus-needle`, and downloads the local models. Restart ViL Agent after setup. The first model download may take a few minutes and requires internet access. Use `DESK_NO_VOICE=1` to disable voice initialization.

## Windows agent

Build the Windows executable from Linux with the project script:

```bash
./tools/windows/build_windows.sh
```

The result is `output/desk_ctrl_agent.exe`. Copy it to the Windows computer and run it. Allow the program through Windows Firewall on **Private networks**. The phone and computer must be on the same Wi-Fi network for Wi-Fi pairing.

For USB, copy `adb.exe` into the same folder as the agent, enable USB debugging, connect the phone, and approve the computer.

Windows currently does not provide Linux's Bluetooth transport, voice engine, automatic keyboard focus detection, volume/brightness levels, or Linux-specific brightness keys. The Windows build uses native Windows input injection, WASAPI Remote Audio, and includes the tray and autostart features. Remote Audio output-device discovery is supported, but source playback must remain enabled while capturing on Windows.

## Useful agent options

```bash
DESK_PORT=8765       # Change the Wi-Fi port
DESK_TOKEN=mytoken   # Use a fixed token for a test or controlled setup
DESK_NO_USB=1        # Disable USB auto-connect for demos or tests
DESK_NO_VOICE=1      # Disable voice initialization
DESK_DEBUG=1         # Print focus decisions
```

The agent stores its pairing token in `~/.config/deskctrl/token` on Linux and `%APPDATA%\\deskctrl\\token` on Windows. The token is kept across restarts so paired phones can reconnect.

## Test the project

Run the complete mobile and agent test suites:

```bash
export PATH="$HOME/dev/flutter/bin:$PATH"

cd mobile
flutter analyze
flutter test

cd ../agent
cargo test
```

Run the Windows agent tests under Wine, if the cross-build environment is installed:

```bash
cd /path/to/desk_ctrl
./tools/windows/build_windows.sh test
```

For real-phone testing, use a recording fake agent and verify the active computer before sending input. A phone tap can send keys or mouse events to the active computer. The complete safe procedure is documented in [`okf/TESTING.md`](okf/TESTING.md).

## Troubleshooting

### The phone cannot find the agent

- Confirm both devices are on the same Wi-Fi network.
- Confirm the agent is running and its port is `8765`.
- Allow the agent through the computer firewall.
- Use the QR code or manually enter the exact IP address, port, and token.
- For USB, check `adb devices` and approve the debugging prompt on the phone.

### The agent starts but keyboard or mouse input does not work on Linux

Run `sudo ./output/setup_laptop.sh`, then log out and back in if requested. Check that `/dev/uinput` exists and that the current user has permission to access it.

### The phone was disconnected

The app automatically tries the remembered computer through another available medium. The connection icon shows which medium is active. Reconnect the USB cable or restart the agent if all mediums are unavailable.

### The agent port is already in use

Stop the other copy of ViL Agent, or select another port:

```bash
DESK_PORT=8790 ./output/desk_ctrl_agent
```

The phone must use the same port when pairing manually.

### Remote Audio is unavailable on Linux

Install the PulseAudio client utilities (`pulseaudio-utils` on Debian/Ubuntu), and confirm that `pactl info`, `parec --help`, and `pacat --help` work in the same desktop login session as ViL Agent. PipeWire systems need the PipeWire Pulse compatibility service. Remote Audio cannot start through a Bluetooth-only ViL connection.

## More documentation

The [`okf/`](okf/) directory is the project's detailed, maintained knowledge base:

- [`okf/INDEX.md`](okf/INDEX.md) — where to find each technical topic
- [`okf/FEATURES.md`](okf/FEATURES.md) — user-visible behavior
- [`okf/ARCHITECTURE.md`](okf/ARCHITECTURE.md) — system design and data flow
- [`okf/PROTOCOL.md`](okf/PROTOCOL.md) — phone-to-agent protocol
- [`okf/OPERATIONS.md`](okf/OPERATIONS.md) — build, install, and shipping commands
- [`okf/TESTING.md`](okf/TESTING.md) — test strategy and safe phone testing
- [`okf/KNOWN.md`](okf/KNOWN.md) — known limitations and open work

## License

No open-source license has been selected for this repository yet. Treat the source as private project code unless the project owner adds a license.
