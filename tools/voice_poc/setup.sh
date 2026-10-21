#!/usr/bin/env bash
# One-time setup: a Python environment with Whistle/Needle and a small offline voice for test speech.
# Needs internet once (about 150 MB: Python packages, the Piper voice, the two models are fetched on first run).
set -euo pipefail
HOME_DIR="$HOME/voice_poc"
mkdir -p "$HOME_DIR/tts" "$HOME_DIR/audio"
if command -v uv >/dev/null 2>&1; then
  uv venv "$HOME_DIR/env" -q
  uv pip install -q --python "$HOME_DIR/env/bin/python" cactus-needle piper-tts
else
  python3 -m venv "$HOME_DIR/env"
  "$HOME_DIR/env/bin/python" -m pip install -q cactus-needle piper-tts
fi
for f in en_US-amy-low.onnx en_US-amy-low.onnx.json; do
  # no resuming: continuing a half-finished file produced a corrupt voice once
  [ "$f" = en_US-amy-low.onnx ] && [ "$(stat -c %s "$HOME_DIR/tts/$f" 2>/dev/null || echo 0)" -eq 63104526 ] && continue
  rm -f "$HOME_DIR/tts/$f"
  curl -fL --retry 5 --retry-delay 3 -o "$HOME_DIR/tts/$f" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low/$f"
done
size=$(stat -c %s "$HOME_DIR/tts/en_US-amy-low.onnx")
[ "$size" -eq 63104526 ] || { echo "voice download is incomplete ($size bytes): run setup.sh again"; exit 1; }
echo "setup done: $HOME_DIR"
