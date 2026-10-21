# Voice proof of concept: Cactus Whistle (speech to text) + Needle 3 (text to action)

Question it answers: are Whistle and Needle accurate and fast enough to control a computer by voice
(dictation and commands) in DeskCtrl, and are Android engine files published?

## Run (Linux/macOS, Python 3.9+, internet once)
```
./setup.sh              # environment + test voice (about 150 MB)
./run.sh audio          # makes 13 test clips with an offline TTS voice
./run.sh asr            # Whistle: text, time per clip, with/without keyword biasing
./run.sh needle         # Needle 3: spoken text -> tool call, confidence, time
./run.sh android        # lists the Android engine files and sizes (no download)
```
The first `asr` and `needle` run downloads the models (Whistle 17 MB, Needle 3 8-29 MB) into `~/.cache/cactus-needle`.
`run.sh` limits CPU priority, threads, memory (4 GB) and time (10 min) so nothing can freeze the machine.
Telemetry of the package is switched off (`NEEDLE_TELEMETRY=0`, `DO_NOT_TRACK=1`).
To stop earlier: `POC_QUERIES=5 ./run.sh needle` runs only the first 5 queries.

## Send back
Copy the whole output of `./run.sh asr` and `./run.sh needle` (and `android`), plus the machine (CPU, RAM).

## Results measured so far (Whistle only, on the developer machine)
| clip | Whistle heard | ms |
|---|---|---|
| "open a terminal" | Open a terminal | 18 |
| "scroll down a bit" | Scroll down a bit. | 22 |
| "turn the volume up" | Turn the volume up. | 23 |
| "please paste that here" | Please paste that here. | 23 |
| "press enter" | Press enter. | 16 |
| "copy" | Happy. (one word: fails) | 14 |
| "close this window" | Flose this window. | 24 |
| "refresh the page" | We fresh the page. -> with keywords: Refresh the page. | 19 |
| "undo that" | And do that. -> with keywords: Undo that. | 16 |
| 6 s sentence | exact, "3:30" written "330" | 429 |
| 15 s sentence | one comma error | 815 |
Needle 3 was not measured: the run froze the machine, hence the safety limits above.

## Results measured on a second, weak machine (AMD A4-3350B 2012, 4 threads, 6.9 GB, no AVX, busy desktop)
Whistle: 1.6-4 s for 1-2 s commands, 10 s for a 6 s sentence, 23 s for 15 s (about 1.5x real time at nice 19, 2 threads).
Needle 3: load 45 s (first run also downloads), 4.4-13 s per query, 3.4 GB RAM in use on the box in total.
Needle picked the right action in 11 of 16 command queries; wrong: "close the tab" -> Tab key (confidence 0.86),
"tell me a joke" -> close_tab (0.15); missed: close this window, reload the page, double click.
Confidence does not separate right from wrong (right answers 0.16-0.70, a wrong one 0.86).
Android engine files exist: android-arm64/libneedle.a 2.2 MB (+ needle.h, CLI 1.5 MB).
