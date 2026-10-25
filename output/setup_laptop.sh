#!/usr/bin/env bash
# One-time setup for the ViL agent on a Linux computer.
#
#   sudo ./setup_laptop.sh
#
# Afterwards just double-click "ViL Agent" on the Desktop (or find it in the
# app menu). No sudo is needed to run it again, also after a reboot.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this with sudo:  sudo $0" >&2
    exit 1
fi

USER_NAME="${SUDO_USER:-}"
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = root ]; then
    echo "Run it as your normal user with sudo (not from a root shell), so I know who to set this up for." >&2
    exit 1
fi
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
USER_ID="$(id -u "$USER_NAME")"

HERE="$(cd "$(dirname "$0")" && pwd)"
AGENT_SRC="$HERE/desk_ctrl_agent"
if [ ! -f "$AGENT_SRC" ]; then
    echo "desk_ctrl_agent must be in the same folder as this script ($HERE)." >&2
    exit 1
fi

echo "1/4 Allowing $USER_NAME to create virtual keyboard/mouse devices (/dev/uinput)..."
# "uaccess" gives the user who is logged in at the computer access straight away;
# the "input" group is the fallback (needs a log out and in).
cat > /etc/udev/rules.d/99-deskctrl-uinput.rules <<'EOF'
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF
echo uinput > /etc/modules-load.d/deskctrl-uinput.conf
modprobe uinput
udevadm control --reload-rules
udevadm trigger --subsystem-match=misc --sysname-match=uinput || true
usermod -aG input "$USER_NAME"

echo "2/4 USB and Remote Audio support: installing desktop helper tools..."
if ! command -v adb >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y adb android-sdk-platform-tools-common || echo "Could not install adb; install it yourself for USB support." >&2
    else
        echo "Install adb (android-tools) with your package manager for USB support." >&2
    fi
fi
if ! command -v pactl >/dev/null 2>&1 || ! command -v parec >/dev/null 2>&1 || ! command -v pacat >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y pulseaudio-utils || echo "Could not install PulseAudio tools; install pactl, parec and pacat yourself for Remote Audio." >&2
    else
        echo "Install PulseAudio client tools (pactl, parec and pacat) with your package manager for Remote Audio." >&2
    fi
fi

echo "3/4 Installing the agent to /usr/local/bin/desk_ctrl_agent..."
install -Dm755 "$AGENT_SRC" /usr/local/bin/desk_ctrl_agent

echo "4/4 Adding the launcher..."
install -Dm644 "$HERE/vil-icon.png" /usr/share/icons/hicolor/256x256/apps/vil-agent.png
LAUNCHER='[Desktop Entry]
Type=Application
Name=ViL Agent
Icon=vil-agent
Comment=Control this computer from your phone
Exec=/usr/local/bin/desk_ctrl_agent
Terminal=false
Categories=Utility;
'
printf '%s' "$LAUNCHER" > /usr/share/applications/deskctrl-agent.desktop
chmod 644 /usr/share/applications/deskctrl-agent.desktop

DESK="$(sudo -u "$USER_NAME" env HOME="$USER_HOME" xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -d "$DESK" ] || DESK="$USER_HOME/Desktop"
if [ -d "$DESK" ]; then
    ICON="$DESK/ViL Agent.desktop"
    printf '%s' "$LAUNCHER" > "$ICON"
    chown "$USER_NAME": "$ICON"
    chmod +x "$ICON"
    # Ubuntu/GNOME wants the icon marked as trusted; harmless elsewhere.
    sudo -u "$USER_NAME" env HOME="$USER_HOME" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
        gio set "$ICON" metadata::trusted true 2>/dev/null || true
    echo "   Desktop icon: $ICON"
fi

echo
if sudo -u "$USER_NAME" test -w /dev/uinput; then
    echo "Done. Double-click \"ViL Agent\" on the Desktop."
else
    echo "Done. One more step: log out and log back in (or reboot) so the new permission applies,"
    echo "then double-click \"ViL Agent\" on the Desktop."
fi
echo "If the icon asks, choose \"Allow Launching\" / \"Trust and Launch\" once."
