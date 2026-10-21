#!/usr/bin/env bash
# Builds output/desk_ctrl_agent.exe (the Windows agent) on Linux, without sudo and without Windows:
#   rustup target add x86_64-pc-windows-gnu   +   zig (pip package "ziglang") as the linker.
# Tests of the Windows build run under Wine:   ./tools/windows/build_windows.sh test
# Needs about 3 GB of disk for the build (kept in ~/winbuild, delete it when done).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WB="$HOME/winbuild"
mkdir -p "$WB"
rustup target add x86_64-pc-windows-gnu >/dev/null
if [ ! -x "$WB/zigenv/bin/python" ]; then
  uv venv -q "$WB/zigenv"
  uv pip install -q --python "$WB/zigenv/bin/python" ziglang
fi
cp "$ROOT/tools/windows/zigcc.py" "$WB/zigcc.py"
chmod +x "$WB/zigcc.py"
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="$WB/zigcc.py"
cd "$ROOT/agent"
if [ "${1:-}" = "test" ]; then
  export WINEDEBUG=-all WINEPREFIX="$HOME/.wine-deskctrl"
  CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUNNER=wine cargo test --target x86_64-pc-windows-gnu --target-dir "$WB/target"
  rm -rf "$WB/target/x86_64-pc-windows-gnu/debug"   # keep the disk free
else
  cargo build --release --target x86_64-pc-windows-gnu --target-dir "$WB/target"
  cp "$WB/target/x86_64-pc-windows-gnu/release/agent.exe" "$ROOT/output/desk_ctrl_agent.exe.new"
  mv "$ROOT/output/desk_ctrl_agent.exe.new" "$ROOT/output/desk_ctrl_agent.exe"
  echo "built: $ROOT/output/desk_ctrl_agent.exe"
fi
