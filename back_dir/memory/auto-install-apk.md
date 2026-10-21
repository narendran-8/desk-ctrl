---
name: auto-install-apk
description: "After every app change, build the APK and install it on the user's phone via adb without being asked"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 7e7fe918-7750-4258-911e-18dae3d7c9cc
  modified: 2026-10-13T17:50:19.435Z
---

After any change to the mobile app, run the tests, build the release APK, copy it to `output/desk_ctrl.apk` and install it on the connected phone with `adb install -r` — every time, without waiting for "install now".

**Why:** the user said "when each update you install the app automatically" (2026-10-13) after repeatedly having to ask "install now".

**How to apply:** build with `export PATH=$HOME/dev/flutter/bin:$PATH ANDROID_HOME=$HOME/dev/android-sdk; cd mobile && flutter build apk --release`, then `timeout 120 adb install -r ../output/desk_ctrl.apk`. If `adb devices` shows no phone, say so and keep the APK in `output/`. Desktop-agent changes: copy the binary to `output/desk_ctrl_agent` with `cp` to a `.new` file then `mv` (the old file may be running). Don't tap around the phone UI unless needed — the screen may be locked and real computers may be connected (taps on keys would type on them).
