---
id: okf
summary: The OKF format - file anatomy, size budgets, and the exact steps to keep the knowledge base current.
updated: 2026-10-21
sources: [okf/okf.py]
---
# OKF (open knowledge format) - how this folder works

Goal: an agent can understand and safely change the project reading **a few hundred lines, not the whole code**.
All knowledge lives flat in `okf/` (one directory, no sub-folders).

## Reading order (token-cheap)
1. `INDEX.md` (~60 lines): routing table + rules.  2. `LATEST.md` (last 12 updates).  3. Only the topic files the task needs.
`okf.json` is the same index as data (file, summary, updated, sources, lines, approx_tokens) for tools.

## Anatomy of a topic file
```
---
id: short-id
summary: one line, what is in here and when to read it
updated: YYYY-MM-DD        # last day the content was checked/changed
sources: [agent/src/x.rs, mobile/lib/y.dart]   # code the doc describes (used to detect staleness)
---
# Title
facts as tables / short bullets, no story telling. Code names in `backticks`. Paths relative to the project root.
```
Budget: **<= 160 lines per file** (enforced by `check`), ~1.5k tokens. Too long -> split by topic, add the new file to `INDEX.md`.
Style: present tense, facts first, one fact per line, tables for lists, no history in topic files (history lives in
`LATEST.md` / `CHANGELOG.md`). Say *why* only in `DECISIONS.md`. Mark unknowns as `UNKNOWN:`; never guess silently.

## Files
| File | Role |
|---|---|
| `INDEX.md` | routing table, commands, rules. Keep ~60 lines. |
| `LATEST.md` | newest 12 updates, newest first. Format below. |
| `CHANGELOG.md` | everything older, newest first. Append-only. |
| `ARCHITECTURE.md` `PROTOCOL.md` `AGENT.md` `MOBILE.md` `SETTINGS.md` `FEATURES.md` | what the system is |
| `TESTING.md` `OPERATIONS.md` | how to verify / build / ship |
| `DECISIONS.md` `KNOWN.md` | why, and what is left |
| `okf.py`, `okf.json` | tool and generated manifest |

## Update protocol (do this at the end of every task)
1. Edit the topic files whose facts changed (and only those). Bump nothing by hand.
2. `python3 okf/okf.py log "Short title" -d MOBILE,SETTINGS -f mobile/lib/x.dart,agent/src/y.rs -t "phone 162 / agent 45 pass" -n "one-line caveat"`
   - adds the entry on top of `LATEST.md`, moves the 13th-oldest into `CHANGELOG.md`, stamps `-d` docs with today, rebuilds `okf.json`.
3. Change of counts/state? Update the "State now" line in `INDEX.md`.
4. `python3 okf/okf.py check` must print `OKF ok`. `STALE?` lines tell you which doc's source code changed after the doc was updated.
5. New topic file? add front matter + a row in `INDEX.md`'s table + `OKF.md` table; `check` fails otherwise.

## LATEST.md entry format
`## YYYY-MM-DD · title` then bullets `files:` `docs:` `tests:` `note:` (only the ones that apply). One entry per task, 2-5 lines.

## Commands
`check` (validate) · `stale` (docs behind their code) · `log` (add entry) · `touch DOC` (stamp only) · `manifest` (rebuild okf.json).
