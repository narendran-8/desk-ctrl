#!/usr/bin/env bash
# Runs one step with safety limits so a problem cannot freeze the machine:
#   - lowest CPU priority, at most 2 threads
#   - at most 4 GB of memory (the step is killed instead of the computer freezing)
#   - at most 10 minutes
# Usage: ./run.sh audio | asr | needle | android
cd "$(dirname "$0")"
PY="$HOME/voice_poc/env/bin/python"
export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2 NEEDLE_TELEMETRY=0 DO_NOT_TRACK=1
case "${1:-}" in
  audio)   script=make_audio.py ;;
  asr)     script=asr.py ;;
  needle)  script=nd.py ;;
  android) script=android_libs.py ;;
  *) echo "usage: $0 audio|asr|needle|android"; exit 1 ;;
esac
ulimit -v 4194304            # 4 GB of address space (KB)
exec nice -n 19 timeout 600 "$PY" "$script"
