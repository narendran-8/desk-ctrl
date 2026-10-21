DeskCtrl agent for Windows (desk_ctrl_agent.exe)
================================================

Turns the phone into a keyboard, trackpad and mouse for this Windows PC.

1. Copy desk_ctrl_agent.exe to a folder of your own (for example C:\DeskCtrl) and double-click it.
   Windows SmartScreen may say "Windows protected your PC" because the file is not signed:
   click "More info" > "Run anyway".
2. The first time, Windows Firewall asks whether the agent may talk on the network: allow it on
   PRIVATE networks (your home Wi-Fi). Or run allow_firewall.bat once as administrator.
3. On the phone open DeskCtrl, scan the QR code in the agent window (or type the Wi-Fi address,
   port and token shown there). Phone and PC must be on the same Wi-Fi.
4. The phone remembers the PC (the token is kept in %APPDATA%\deskctrl\token), so next time it
   connects by itself when the agent is running. Settings > "Start the agent when I log in" starts
   the agent with Windows.

USB cable (optional): put adb.exe (Google's "SDK Platform-Tools", from
https://developer.android.com/tools/releases/platform-tools) in the same folder as
desk_ctrl_agent.exe, turn on USB debugging on the phone, plug it in and allow the PC. The phone
is then connected and paired by itself.

Not available on Windows yet: Bluetooth, the phone's volume / brightness percentages, the
auto-keyboard (switching to the keyboard when a text field is focused), Voice, and the
brightness keys. Keys that exist only on Linux (for example "Open terminal" = Ctrl+Alt+T) do
nothing there.

Remove it: Settings > untick "Start the agent when I log in", close the window, delete the folder
(and %APPDATA%\deskctrl if you want to forget the pairing).
