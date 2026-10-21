"""Needle 3 (text -> tool call): which action does a spoken command mean?  One line per query,
printed as soon as it is done, so you can see where it stops if something goes wrong."""
import json, os, time

os.environ["NEEDLE_TELEMETRY"] = "0"
os.environ["DO_NOT_TRACK"] = "1"
import needle
from tools_def import TOOLS

QUERIES = [
    "open a terminal", "Open terminal please", "Flose this window.", "close this window", "close the tab",
    "Happy.", "copy that", "paste", "And do that.", "undo that", "We fresh the page.", "reload the page",
    "scroll down a bit", "scroll all the way up", "turn the volume up", "mute", "right click", "double click",
    "press enter three times", "delete the last word", "select all and copy",
    "What is the weather like today?", "Hello team, the meeting is moved to 330 on Friday.", "tell me a joke",
]
LIMIT = int(os.environ.get("POC_QUERIES", len(QUERIES)))

t = time.perf_counter()
print("loading Needle ...", flush=True)
agent = needle.Needle(tools=TOOLS)
print(f"loaded in {time.perf_counter() - t:.1f} s", flush=True)
for q in QUERIES[:LIMIT]:
    agent.reset()
    t = time.perf_counter()
    r = agent.complete(q)
    ms = (time.perf_counter() - t) * 1000
    calls = [(c.get("name"), c.get("arguments")) for c in r.get("function_calls", [])]
    print(f"{ms:6.0f} ms conf={r.get('confidence')!s:6} {q!r:58} -> {json.dumps(calls)}", flush=True)
