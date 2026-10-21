"""Whistle (speech -> text) on the test clips: text, time, with and without keyword biasing."""
import glob, os, time, wave

os.environ["NEEDLE_TELEMETRY"] = "0"   # the package reports usage by default: off
os.environ["DO_NOT_TRACK"] = "1"
import needle

AUDIO = os.environ.get("POC_AUDIO", os.path.expanduser("~/voice_poc/audio"))
KEYWORDS = ["terminal", "copy", "paste", "scroll", "refresh", "undo", "enter", "volume", "window", "close"]

files = sorted(glob.glob(f"{AUDIO}/*.wav"))
print(f"{len(files)} clips in {AUDIO}", flush=True)
for path in files:
    with wave.open(path) as w:
        dur = w.getnframes() / w.getframerate()
    t = time.perf_counter()
    plain = needle.transcribe(path)["text"]
    ms = (time.perf_counter() - t) * 1000
    t = time.perf_counter()
    biased = needle.transcribe(path, keywords=KEYWORDS)["text"]
    msk = (time.perf_counter() - t) * 1000
    print(f"{os.path.basename(path):18} {dur:5.1f}s {ms:6.0f} ms  {plain!r}", flush=True)
    if biased != plain:
        print(f"{'  with keywords':18} {'':6} {msk:6.0f} ms  {biased!r}", flush=True)
