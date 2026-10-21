#!/usr/bin/env python3
"""DeskCtrl voice helper: Whistle (speech -> text) and Needle 3 (text -> action) behind a tiny
line protocol, so the agent keeps the models loaded between phrases.

stdin  : one JSON object per line   {"op": "transcribe", "wav": "/tmp/x.wav", "mode": "dictate|command"}
                                    {"op": "intent", "text": "close the tab"}
                                    {"op": "prefetch"}   (downloads both models, then exits)
stdout : one JSON object per line   {"t": "text", "text": "...", "ms": 12}
                                    {"t": "intent", "calls": [{"name": "copy"}], "confidence": 0.6, "ms": 9}
                                    {"t": "error", "msg": "..."}
Everything stays on this computer. The package's usage reporting is switched off.
"""
import json
import os
import sys
import time

os.environ["NEEDLE_TELEMETRY"] = "0"
os.environ["DO_NOT_TRACK"] = "1"
os.environ.setdefault("OMP_NUM_THREADS", "2")
# NOTE: do not pin this process to a few cores or give it a CPU quota. The engine starts one
# busy-waiting thread per core of the machine; with fewer cores than that a 1 s recognition takes
# minutes. The agent starts this helper in the idle scheduling class instead.

# Words Whistle is nudged towards when a command (not dictation) is expected.
KEYWORDS = [
    "copy", "cut", "paste", "undo", "redo", "select all", "find", "save", "enter", "backspace", "delete",
    "escape", "tab", "refresh", "reload", "terminal", "close", "window", "scroll", "volume", "mute", "click",
    "home", "end", "page up", "page down", "new tab", "close tab", "zoom", "workspace", "overview",
    "screenshot", "brightness", "play", "pause", "next", "previous", "arrow", "lock", "drag", "release",
]

# One narrow tool per action: the ids are the ones in the phone's round menu (edit_menu.dart).
ACTIONS = {
    "copy": "Copy the selection", "cut": "Cut the selection", "paste": "Paste the clipboard",
    "undo": "Undo the last change", "redo": "Redo the undone change", "select_all": "Select everything",
    "find": "Open search in the page or document", "save": "Save the file",
    "enter": "Press the Enter key", "backspace": "Delete the character before the cursor",
    "delete": "Delete the character after the cursor", "escape": "Press the Escape key",
    "tab": "Press the Tab key", "refresh": "Reload the web page", "open_terminal": "Open a terminal window",
    "close_app": "Close the window or application in front", "new_tab": "Open a new browser tab",
    "close_tab": "Close the current browser tab", "page_up": "Page up", "page_down": "Page down",
    "home": "Jump to the start of the line", "end": "Jump to the end of the line",
    "scroll_up": "Scroll the page up", "scroll_down": "Scroll the page down",
    "volume_up": "Make the sound louder", "volume_down": "Make the sound quieter", "mute": "Mute the sound",
    "click": "Click the left mouse button", "right_click": "Click the right mouse button",
    "double_click": "Double click the left mouse button", "middle_click": "Click the middle mouse button",
    "terminal_copy": "Copy inside a terminal window", "terminal_paste": "Paste inside a terminal window",
    "drag_start": "Press and hold the mouse button to start dragging", "drag_end": "Release the mouse button to drop",
    "scroll_left": "Scroll the page to the left", "scroll_right": "Scroll the page to the right",
    "scroll_top": "Scroll to the top of the page", "scroll_bottom": "Scroll to the bottom of the page",
    "zoom_in": "Zoom in, make the page bigger", "zoom_out": "Zoom out, make the page smaller",
    "workspace_left": "Switch to the workspace on the left", "workspace_right": "Switch to the workspace on the right",
    "overview": "Show the overview of all windows", "screenshot": "Take a screenshot",
    "brightness_up": "Make the screen brighter", "brightness_down": "Make the screen dimmer",
    "play_pause": "Play or pause the music or video", "next_track": "Next song or track",
    "prev_track": "Previous song or track", "seek_forward": "Skip forward in the video",
    "seek_back": "Skip backward in the video", "next_window": "Switch to the next window",
    "prev_window": "Switch to the previous window", "next_tab": "Switch to the next browser tab",
    "prev_tab": "Switch to the previous browser tab", "move_left": "Move the mouse cursor to the left",
    "move_right": "Move the mouse cursor to the right", "move_up": "Move the mouse cursor up",
    "move_down": "Move the mouse cursor down", "arrow_left": "Press the left arrow key",
    "arrow_right": "Press the right arrow key", "arrow_up": "Press the up arrow key",
    "arrow_down": "Press the down arrow key", "space": "Press the space bar",
    "lock_screen": "Lock the computer screen",
}
TOOLS = [
    {"name": name, "description": text, "parameters": {"type": "object", "properties": {}}}
    for name, text in ACTIONS.items()
]

_agent = None


def heal_cache():
    """A model download that was cut off (power loss, killed process) leaves an empty or short
    file that the package then trusts forever ("needle_load failed"). Remove such files so the
    package downloads them again."""
    import glob

    root = os.path.join(os.path.expanduser("~"), ".cache", "cactus-needle")
    for path in glob.glob(os.path.join(root, "**", "*.cact"), recursive=True):
        try:
            if os.path.getsize(path) < 1_000_000:
                os.remove(path)
        except OSError:
            pass


def transcribe(req):
    heal_cache()
    import needle

    started = time.perf_counter()
    kwargs = {"keywords": KEYWORDS} if req.get("mode") == "command" else {}
    text = needle.transcribe(req["wav"], **kwargs)["text"].strip()
    return {"t": "text", "text": text, "ms": round((time.perf_counter() - started) * 1000)}


def intent(req):
    global _agent
    heal_cache()
    import needle

    if _agent is None:
        _agent = needle.Needle(tools=TOOLS)
    _agent.reset()
    started = time.perf_counter()
    r = _agent.complete(req["text"])
    calls = [{"name": c.get("name"), "arguments": c.get("arguments") or {}} for c in r.get("function_calls", [])]
    return {
        "t": "intent",
        "calls": [c for c in calls if c["name"] in ACTIONS],
        "confidence": r.get("confidence"),
        "ms": round((time.perf_counter() - started) * 1000),
    }


def prefetch(_req):
    import wave
    import tempfile

    path = os.path.join(tempfile.mkdtemp(), "silence.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\0\0" * 16000)
    transcribe({"wav": path})
    intent({"text": "copy"})
    return {"t": "ready"}


def main():
    ops = {"transcribe": transcribe, "intent": intent, "prefetch": prefetch}
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            out = ops[req["op"]](req)
        except Exception as e:  # keep serving: one bad request must not end the helper
            out = {"t": "error", "msg": f"{type(e).__name__}: {e}"}
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
        if out.get("t") == "ready":
            break


if __name__ == "__main__":
    main()
