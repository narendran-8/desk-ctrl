---
name: okf-maintenance
description: Keep the okf/ knowledge base current after every change; read okf/INDEX.md first instead of scanning code
metadata:
  type: feedback
---

The user wants an OKF (open knowledge format) folder `okf/` in the project root that documents everything and is updated with every change, so agents read little and understand fast (token saving).

**Why:** asked on 2026-10-14 ("create OKF... every update, okf is update... latest update also noted, to reduce token usage, all created files in same dir").

**How to apply:** at the start of a task read `okf/INDEX.md` then `okf/LATEST.md` (not the whole code). At the end: edit the topic files whose facts changed, run `python3 okf/okf.py log "title" -d DOC,DOC -f files -t "tests"` and `python3 okf/okf.py check` (must print `OKF ok`). Format rules are in `okf/OKF.md`; root `CLAUDE.md` points to it. Keep each topic file <= 160 lines. Related: [[auto-install-apk]].
