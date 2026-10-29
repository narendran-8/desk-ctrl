---
id: latest
summary: The 12 newest updates, newest first (what changed, files, tests, caveats). Read this to know the current state of work.
updated: 2026-10-29
sources: []
---
# Latest updates (newest first; older ones are in CHANGELOG.md)
Entry format: `## date · title` + `files:` `docs:` `tests:` `note:`. Add entries with `python3 okf/okf.py log ...`.

## 2026-10-29 · Silence phone media during computer-only audio sharing
- files: mobile/lib/settings.dart, mobile/lib/settings_sheet.dart, mobile/lib/remote_audio.dart, mobile/lib/remote_audio_sheet.dart, mobile/android/app/src/main/AndroidManifest.xml, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PlaybackCaptureBridge.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PlaybackCaptureService.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PhoneMediaVolume.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PhoneVolumeLease.kt, mobile/test/phone_audio_source_test.dart, tools/audio/PhoneVolumeLeaseTest.kt, tools/audio/PcmPumpTest.kt, tools/audio/test_pcm_pump.py, README.md
- docs: ARCHITECTURE, MOBILE, FEATURES, SETTINGS, TESTING, KNOWN, DECISIONS
- tests: Flutter279 passed with1 opt-in soak skipped (serial rerun); analyzer12 existing infos; Kotlin volume-lease/PCM tests passed; APK built/installed; actual phone media volume15 ->0 with1705 nonzero test-tone frames ->15 on Stop; capture service removed
- note: Also play on this phone defaults off (computer only), switch on for both. Previous media volume restored on Stop/error/revocation; interrupted-process recovery on next launch. Calls/alarms/ringer unchanged. Desktop/protocol unchanged. First build-concurrent run3 existing timing failures, serial full suite passed. Test pairing/tunnel/receiver removed, Computer2 restored.

## 2026-10-29 · Stream phone media to connected computer speakers
- files: mobile/lib/remote_audio.dart, mobile/lib/remote_audio_sheet.dart, mobile/lib/settings.dart, mobile/android/app/src/main/AndroidManifest.xml, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/MainActivity.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PlaybackCaptureBridge.kt, mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PlaybackCaptureService.kt, mobile/test/phone_audio_source_test.dart, mobile/test/remote_audio_test.dart, README.md
- docs: INDEX, ARCHITECTURE, MOBILE, FEATURES, SETTINGS, PROTOCOL, TESTING, KNOWN
- tests: Flutter 279 passed with 1 opt-in soak skipped; focused phone-source 4 passed; Linux agent 82 passed; analyzer 12 existing infos; release APK built/installed; actual Android Chrome tone: 14402 PCM frames, 5034 nonzero; Stop removed service
- note: Android10+ permission/MediaProjection consent; capture-allowing apps only, no microphone/screen images/storage. Phone may remain audible. Uses existing desktop sink protocol, no agent upgrade. Physical Windows listening and precise latency unmeasured. Test pairing/tunnel/receiver removed; Computer2 restored.

## 2026-10-26 · Move seek buttons to track title and add title swipes
- files: mobile/lib/now_playing.dart, mobile/lib/pad_screen.dart, mobile/lib/edge_zones.dart, mobile/test/media_timeline_test.dart, README.md
- docs: MOBILE, FEATURES, TESTING
- tests: Flutter 275 passed with one soak skipped; focused media 20 passed; title swipe direction/isolation/small-touch/track-change tests passed; analyzer 12 existing infos; APK built/installed; actual phone title swipes and relocated holds verified
- note: Title row is << icon + name >>; right swipe seeks forward 10 seconds, left backward 10; existing tap/hold preserved. Split timeline stays above. Media overlay y=0..64 remains outside pointer Listener. Test source/tunnel removed, original Computer 2 restored. Desktop unchanged.

## 2026-10-26 · Split playback progress around the play-pause button
- files: mobile/lib/split_media_seek_bar.dart, mobile/lib/now_playing.dart, mobile/test/media_timeline_test.dart, README.md
- docs: INDEX, MOBILE, FEATURES, TESTING
- tests: Flutter 275 passed with one soak skipped; focused media 20 passed; playhead clearance at compact/full widths and cross-gap drag passed; analyzer 12 existing infos; APK built/installed; actual phone midpoint/drag/play UI checked
- note: Two progress halves share one timeline with a 38dp center control slot; dot never painted behind play. Existing time labels/seek clock preserved. Test source/tunnel removed, original Computer 2 restored. Desktop unchanged.

## 2026-10-26 · Prevent playback clock resetting after seek preview timeout
- files: mobile/lib/connection.dart, mobile/lib/now_playing.dart, mobile/test/media_timeline_test.dart, README.md
- docs: INDEX, MOBILE, FEATURES, TESTING, KNOWN
- tests: Flutter 274 passed with one soak skipped; focused media 19 passed; stale zero/advancing old samples/pause/confirmation regressions passed; analyzer 12 existing infos; APK built and installed; actual phone checked at 7 and 13 seconds
- note: Old APK reset to 0:00 at 7 seconds after 2:30 seek. Fixed APK showed ~2:37 while feedback stale, then confirmed 2:43 at 13 seconds. Session clock survives widget preview expiry; estimate explicitly marked until matching feedback. No desktop upgrade needed. Test source/tunnel removed; original Computer 2 restored.

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

