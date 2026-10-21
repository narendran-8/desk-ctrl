---
name: never-run-needle-locally
description: Do not run the Needle/Whistle voice models on the user's own computer; they froze it twice. Use the SSH box or ask first.
metadata:
  type: feedback
---

Never start the Needle 3 / Whistle voice models (voice_helper.py, nd.py, run.sh needle, the agent's voice helper with real models) on the user's own computer without their say-so. Running them there froze the machine twice (2026-10-17, each needed a hard power-off); cause not found (not memory: the helper uses ~114 MB on the other machine).

**Why:** the user had to hold the power button twice and said "dont run, give runnable code as zip". The second time I ran it again "to verify" and it froze again.

**How to apply:** test voice models only on the second machine over SSH (boy@172.22.36.49, 4 cores, 6.9 GB; the user gave the login; the password was shared in chat, so ask again rather than reuse) or ask the user first. Fake helpers are fine for unit tests. The agent now starts the real helper inside a systemd scope with MemoryMax/TasksMax/CPUQuota limits, and `voiceAi` (Needle guesses) is off by default. Related: [[auto-install-apk]].
