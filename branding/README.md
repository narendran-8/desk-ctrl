# ViL branding

The owner selected `vil-icon.png`, a cyan/green binary bow and arrow joined by a string. The master PNG has a transparent background so the mark can sit on the Android launcher, desktop, and tray backgrounds without a square.
Display names: **ViL** (mobile), **ViL Agent** (desktop).

Run `python3 tools/prepare_branding.py` to regenerate Android legacy/adaptive launcher images,
the desktop PNG and Windows ICO. The original artwork is retained unchanged.
The Windows GNU build embeds the ICO using `x86_64-w64-mingw32-windres` (override `WINDRES`).

Package IDs, saved settings, pairing URLs, config paths and existing executable names retain
their DeskCtrl identifiers for compatibility with installed devices.
