---
id: latest
summary: The 12 newest updates, newest first (what changed, files, tests, caveats). Read this to know the current state of work.
updated: 2026-10-26
sources: []
---
# Latest updates (newest first; older ones are in CHANGELOG.md)
Entry format: `## date · title` + `files:` `docs:` `tests:` `note:`. Add entries with `python3 okf/okf.py log ...`.

## 2026-10-26 · Keep playback timeline stable across seek metadata gaps
- files: agent/src/media.rs, mobile/lib/connection.dart, mobile/lib/now_playing.dart, mobile/test/media_timeline_test.dart, README.md
- docs: INDEX, AGENT, MOBILE, FEATURES, PROTOCOL, TESTING, KNOWN
- tests: Flutter 272 passed with one soak skipped; focused media 17 passed; Linux 82 passed; analyzer 12 existing infos; APK built/installed; Linux release built; phone UI before/after seek reproduction verified
- note: Old UI disappeared after 2:30 seek. Fixed UI retains bar and 6:00 total through four-second null metadata at 2:30, 4:38 and 1:07. Duration cached only for same video; agent fingerprint excludes duration and includes URL. Test source/tunnel cleaned; original Computer 2 restored. Reopen agent for desktop fix.

## 2026-10-26 · Recover Remote Audio socket drops without manual restart
- files: mobile/lib/remote_audio.dart, mobile/lib/remote_audio_sheet.dart, mobile/lib/settings_sheet.dart, mobile/test/remote_audio_test.dart, mobile/test/fake_agent.dart, README.md
- docs: INDEX, MOBILE, FEATURES, SETTINGS, PROTOCOL, TESTING, KNOWN
- tests: Flutter 270 passed with one opt-in soak skipped; Remote Audio 7 passed; separate 3:08 PCM soak with three forced drops and >6000 frames passed; analyzer 12 existing infos; APK built/installed; actual phone UI inspected
- note: Healthy routes stay pinned; standard Ping liveness; original-source/output recovery with capped backoff and generation guards; Stop cancels retries. Enabled auto reconnect on current Computer 2 -> box route. Real-speaker uninterrupted playback not measured; no desktop upgrade required.

## 2026-10-26 · Allow Firefox seek controls without duration metadata
- files: agent/src/media.rs, mobile/lib/now_playing.dart, mobile/lib/connection.dart, mobile/test/media_timeline_test.dart, README.md
- docs: INDEX, AGENT, MOBILE, FEATURES, PROTOCOL, KNOWN, TESTING
- tests: Flutter 268 passed; focused timeline 7 passed; Linux 81 passed; private MPRIS unknown-duration repeated seeks passed; actual phone UI 12 commands across four holds; analyzer 12 existing infos; APK built/installed; Linux release rebuilt
- note: Read-only Firefox inspection confirmed CanSeek=true with missing length. Old APK sent zero commands; fixed APK seeks without duration and shows --:--. Reopen running ViL Agent to load output binary. Cleanup tap may have clicked box; disclosed and original target restored.

## 2026-10-26 · Fix repeated seek holds cancelling on finger drift
- files: mobile/lib/now_playing.dart, mobile/test/media_timeline_test.dart
- docs: INDEX, MOBILE, FEATURES, TESTING
- tests: Flutter 267 passed; timeline 6 passed; repeated-hold regression fails on previous code and passes fixed code; analyzer 12 existing infos; release APK built and installed
- note: Single gesture owner replaces nested IconButton; 18dp movement tolerance; consecutive forward/backward holds verified across feedback rebuilds; no live computer media input sent

## 2026-10-26 · Repeat playback seeking while holding forward or rewind
- files: mobile/lib/now_playing.dart, mobile/test/media_timeline_test.dart, README.md
- docs: INDEX, MOBILE, FEATURES, TESTING
- tests: Flutter 266 passed; focused timeline 5 passed; hold accumulation/release/cancel/track-change/disabled checks passed; analyzer 12 existing infos; APK built and installed
- note: Tap still seeks 10 seconds; hold repeats 10-second seeks every 250ms after 500ms threshold, stopping at boundaries or cancellation; protocol unchanged

## 2026-10-26 · Place playback times inside skip controls
- files: mobile/lib/now_playing.dart, mobile/test/media_timeline_test.dart, README.md
- docs: MOBILE, FEATURES, TESTING
- tests: Flutter 265 passed including compact left-to-right order assertion; analyzer 12 existing style infos; release APK built and installed
- note: Order: previous, rewind, current time, seek line with play/pause, total duration, forward, next. Layout-only change; existing actions preserved.

## 2026-10-26 · Arrange playback controls and times in one row
- files: mobile/lib/now_playing.dart, mobile/lib/edge_zones.dart, mobile/lib/pad_screen.dart, mobile/test/media_timeline_test.dart, README.md
- docs: MOBILE, FEATURES, TESTING
- tests: Flutter 265 passed; focused media 12 passed; compact row rendered; analyzer 12 existing style infos; release APK built and installed
- note: Elapsed | previous rewind seek-line/play-pause forward next | duration, all aligned at y=0..40; title below; +/-10s seek requires existing Linux MPRIS capability; protocol unchanged

## 2026-10-26 · Revert integrated playback line update
- files: mobile/lib/now_playing.dart, mobile/lib/edge_zones.dart, mobile/lib/pad_screen.dart, mobile/test/media_timeline_test.dart, README.md
- docs: MOBILE, FEATURES, TESTING
- tests: Flutter 265 passed; release APK rebuilt; analyzer has 12 existing style infos
- note: Reverts b180a8f only; restores separate timeline from 00ed177. APK installation attempted but no Android device was attached.

## 2026-10-26 · Integrate timeline behind playback controls and fix seek buttons
- files: mobile/lib/now_playing.dart, mobile/lib/edge_zones.dart, mobile/lib/pad_screen.dart, mobile/test/media_timeline_test.dart, README.md
- docs: MOBILE, FEATURES, TESTING
- tests: Flutter 265 passed; focused media 12 passed; direct forward/back seek, 700ms hold-drag, previous/play/next packets and pointer isolation passed; analyzer 12 existing infos; release APK built
- note: Progress line behind controls at y=0; times below, centered title at y=56; +/-10s absolute seeks need existing Linux media capability; protocol unchanged

## 2026-10-26 · Add playback time and draggable media timeline
- files: agent/src/media.rs, agent/src/server.rs, agent/src/bluetooth.rs, mobile/lib/connection.dart, mobile/lib/now_playing.dart, mobile/lib/pad_screen.dart, mobile/test/media_timeline_test.dart, README.md
- docs: INDEX, AGENT, MOBILE, FEATURES, PROTOCOL, ARCHITECTURE, TESTING, KNOWN
- tests: Flutter 265 passed; focused timeline/media 12 passed; Linux 81 passed; private MPRIS absolute seek/stale-track/clamp tests passed; pointer isolation and compact layout passed; analyzer 12 existing infos; Linux/Windows releases and APK built
- note: Requires updated Linux agent and MPRIS seek capability; unknown duration/live streams disable seeking; Windows/local-phone metadata remains unavailable

## 2026-10-26 · Move now-playing title beneath playback controls
- files: mobile/lib/now_playing.dart, mobile/lib/edge_zones.dart, mobile/lib/pad_screen.dart, mobile/test/now_playing_test.dart, README.md
- docs: INDEX, MOBILE, FEATURES, TESTING
- tests: Flutter 261 passed; focused 8 passed; short-title centering and long-title scrolling checked at full/compact sizes; compact hint overlap assertion passed; release APK built and installed
- note: Icon and short title center as one group; long titles scroll within playback strip width; metadata protocol unchanged

## 2026-10-26 · Show track title and app icon below trackpad volume
- files: agent/Cargo.toml, agent/Cargo.lock, agent/src/main.rs, agent/src/server.rs, agent/src/media.rs, mobile/lib/connection.dart, mobile/lib/links.dart, mobile/lib/now_playing.dart, mobile/lib/edge_zones.dart, mobile/lib/pad_screen.dart, mobile/test/now_playing_test.dart, README.md
- docs: INDEX, AGENT, MOBILE, FEATURES, PROTOCOL, ARCHITECTURE, TESTING, KNOWN
- tests: Flutter 259 passed; focused 6 passed; Linux agent 80 passed; private MPRIS and PNG icon checks passed; analyzer 12 existing infos; Linux/Windows releases and 71.6MB APK built; APK installed
- note: Metadata currently Linux MPRIS only; PNG app icons with music-note fallback; Windows and Android local-media titles unavailable

