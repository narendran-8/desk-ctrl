# DeskCtrl - instructions for coding agents

Knowledge base: **`okf/`**. Read `okf/INDEX.md` first (about 60 lines), then `okf/LATEST.md`, then only the topic files the task needs.
Do not scan the whole code base to learn the project; the OKF files say where things are and why.

After every change, before finishing:
1. update the topic files whose facts changed;
2. `python3 okf/okf.py log "Short title" -d DOC,DOC -f changed,files -t "tests result" -n "caveat"`;
3. `python3 okf/okf.py check` must print `OKF ok`.
Rules for building, installing and testing on the real phone are in `okf/OPERATIONS.md` and `okf/TESTING.md`.
