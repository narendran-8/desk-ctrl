"""Synthesise key-click WAVs: 3 packs x 3 kinds (key, space, enter)."""
import math, random, struct, sys, wave

RATE = 44100
random.seed(7)

def render(dur, click_hz, thump_hz, noise, decay, thump_amt):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * decay)
        s = noise * (random.random() * 2 - 1) * math.exp(-t * decay * 2.2)
        s += 0.6 * math.sin(2 * math.pi * click_hz * t) * math.exp(-t * decay * 1.6)
        s += thump_amt * math.sin(2 * math.pi * thump_hz * t) * env
        out.append(s)
    peak = max(abs(x) for x in out) or 1
    return [int(x / peak * 0.8 * 32767) for x in out]

PACKS = {
    # name: (click_hz, thump_hz, noise, decay, thump_amt)
    "mechanical": (3200, 180, 0.7, 90, 0.5),
    "soft":       (1400, 110, 0.25, 70, 0.8),
    "typewriter": (2400, 240, 0.9, 55, 0.4),
}
KINDS = {  # kind: (duration, thump multiplier, pitch multiplier)
    "key":   (0.07, 1.0, 1.0),
    "space": (0.10, 1.4, 0.7),
    "enter": (0.11, 1.3, 0.8),
}
out_dir = sys.argv[1]
for pack, (ch, th, no, de, ta) in PACKS.items():
    for kind, (dur, tm, pm) in KINDS.items():
        data = render(dur, ch * pm, th * pm, no, de, ta * tm)
        with wave.open(f"{out_dir}/{pack}_{kind}.wav", "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", s) for s in data))
