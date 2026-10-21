#!/usr/bin/env bash
# Installs the voice engine for the DeskCtrl agent on this computer (once, needs internet):
#   - a private Python environment in ~/.local/share/deskctrl/voice/env with cactus-needle (Whistle + Needle 3)
#   - the two models (about 17 MB + 8-29 MB), downloaded now so the first phrase is not slow
# Everything runs locally afterwards; the audio never leaves your devices. Usage reporting is switched off.
# Run it next to voice_helper.py (it is in the same folder / zip).
set -euo pipefail
DIR="$HOME/.local/share/deskctrl/voice"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR"
if [ ! -x "$DIR/env/bin/python" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv -q "$DIR/env"
  elif python3 -c "import venv, ensurepip" 2>/dev/null; then
    python3 -m venv "$DIR/env"
  else
    echo "Python's venv is missing. Install it (Debian/Ubuntu: sudo apt install python3-venv) or install 'uv', then run this again."
    exit 1
  fi
fi
if command -v uv >/dev/null 2>&1; then
  uv pip install -q --python "$DIR/env/bin/python" "cactus-needle>=3.2"
else
  "$DIR/env/bin/python" -m pip install -q "cactus-needle>=3.2"
fi
cp "$HERE/voice_helper.py" "$DIR/voice_helper.py"
echo "downloading the models (a few minutes on a slow computer) ..."
echo '{"op":"prefetch"}' | NEEDLE_TELEMETRY=0 DO_NOT_TRACK=1 OMP_NUM_THREADS=2 nice -n 10 "$DIR/env/bin/python" "$DIR/voice_helper.py"
echo "voice engine ready in $DIR - restart the agent."
