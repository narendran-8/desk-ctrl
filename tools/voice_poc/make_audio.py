"""Makes test speech with Piper (offline TTS) for the proof of concept. 16 kHz mono WAV."""
import os, wave
from piper import PiperVoice

HOME = os.path.expanduser("~/voice_poc")
OUT = os.environ.get("POC_AUDIO", f"{HOME}/audio")
VOICE = os.environ.get("POC_VOICE", f"{HOME}/tts/en_US-amy-low.onnx")
PHRASES = {
    "copy": "copy",
    "paste_that": "please paste that here",
    "open_terminal": "open a terminal",
    "close_window": "close this window",
    "scroll_down": "scroll down a bit",
    "enter": "press enter",
    "delete_word": "delete the last word",
    "refresh": "refresh the page",
    "volume_up": "turn the volume up",
    "undo": "undo that",
    "chat": "what is the weather like today",
    "dictation": "Hello team, the meeting is moved to three thirty on Friday, please bring the quarterly report.",
    "long": "Voice control for the desk controller lets you dictate text into any application on the computer, "
            "and run actions such as copy, paste, open a terminal or close the window, using only your phone "
            "microphone and a small model that runs entirely offline.",
}
voice = PiperVoice.load(VOICE)
os.makedirs(OUT, exist_ok=True)
for name, text in PHRASES.items():
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        voice.synthesize_wav(text, w)
    with wave.open(f"{OUT}/{name}.wav") as w:
        print(name, w.getframerate(), "Hz", round(w.getnframes() / w.getframerate(), 1), "s", flush=True)
