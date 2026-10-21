import 'package:flutter/material.dart';

/// Control zones along the edges of the touchpad, like the printed zones on some laptop touchpads:
///  - left edge: slide up / down = volume
///  - right edge: slide up / down = brightness
///  - bottom edge (middle part): slide right = Alt+Tab, left = Alt+Shift+Tab, hold = keep the
///    window switcher open and move through it
///  - top edge (middle part): slide right / left = seek forward / backward
///    (or next / previous track, see [TopEdgeMode]); tap its centre = play / pause
enum EdgeZone { none, volume, brightness, media, windows }

/// What sliding along the top edge does.
enum TopEdgeMode {
  /// Forward / backward in what is playing: the Right and Left arrow keys, which video
  /// players and websites use for seeking.
  seek,

  /// Next / previous track media keys.
  track,
}

TopEdgeMode parseTopEdgeMode(String name) => TopEdgeMode.values.firstWhere(
  (m) => m.name == name,
  orElse: () => TopEdgeMode.seek,
);

/// Switching windows or browser tabs moves the focus around (the page, the address bar, the
/// field of the window in between ...). While the switcher slider is in use, and for a moment
/// after, the phone waits for the focus to settle before acting on it, so the place it ends up
/// decides, not the places it passed.
class SwitchGuard {
  static DateTime _until = DateTime.fromMillisecondsSinceEpoch(0);
  static const grace = Duration(seconds: 2);

  static void touch() => _until = DateTime.now().add(grace);
  static void reset() => _until = DateTime.fromMillisecondsSinceEpoch(0);
  static bool get active => DateTime.now().isBefore(_until);
}

class EdgeZones {
  /// Width of the side strips and height of the top strip.
  static const edge = 40.0;

  /// The side strips start below the top band, which keeps the touchpad on/off button free.
  static const sideTopFraction = 0.25;

  /// The top strip covers the middle 60% of the width; the corners are left alone.
  static const topFrom = 0.2, topTo = 0.8;

  /// Distance a finger travels along a zone for one step (one key press).
  static const sideStepPx = 22.0;
  static const seekStepPx = 60.0;
  static const trackStepPx = 80.0;

  /// A tap this close to the middle of the top strip is play / pause.
  static const centreHalfWidth = 36.0;

  /// Slide distance per window in the switcher.
  static const windowStepPx = 50.0;

  /// Play / pause (HID consumer usage 0xCD).
  static const playPauseKey = 0x80CD;

  /// Mute (HID consumer usage 0xE2): a tap on the volume strip.
  static const muteKey = 0x80E2;

  /// The next / previous track buttons at the two ends of the top strip (shown when the
  /// slide seeks): a tap skips a track, a hold on the rest of the end seeks.
  static const skipHalfWidth = 52.0;
  static const nextKey = 0x80B5, previousKey = 0x80B6;

  /// +1 on the next-track button, -1 on previous-track, 0 elsewhere.
  static int skipButton(Offset p, Size size) {
    if (at(p, size) != EdgeZone.media) return 0;
    if (p.dx - size.width * topFrom <= skipHalfWidth) return -1;
    if (size.width * topTo - p.dx <= skipHalfWidth) return 1;
    return 0;
  }

  /// Whether [p] is on the icon in the middle of the bottom strip (tap: windows <-> tabs).
  static bool isSwitchToggle(Offset p, Size size) =>
      at(p, size) == EdgeZone.windows &&
      (p.dx - size.width / 2).abs() <= centreHalfWidth;

  /// Whether [p] is on the play / pause icon in the middle of the top strip.
  static bool isPlayPause(Offset p, Size size) =>
      at(p, size) == EdgeZone.media &&
      (p.dx - size.width / 2).abs() <= centreHalfWidth;

  /// Which zone a touch at [p] on a pad of [size] falls into.
  static EdgeZone at(Offset p, Size size) {
    if (p.dy > size.height - edge &&
        p.dx > size.width * topFrom &&
        p.dx < size.width * topTo) {
      return EdgeZone.windows;
    }
    if (p.dy < edge &&
        p.dx > size.width * topFrom &&
        p.dx < size.width * topTo) {
      return EdgeZone.media;
    }
    if (p.dy > size.height * sideTopFraction) {
      if (p.dx < edge) return EdgeZone.volume;
      if (p.dx > size.width - edge) return EdgeZone.brightness;
    }
    return EdgeZone.none;
  }

  /// Multiplier for a seek speed setting of 1 (slow) ... 5 (fast); 3 is the normal speed.
  static double speedFactor(int speed) =>
      const [0.4, 0.7, 1.0, 1.6, 2.5][speed.clamp(1, 5) - 1];

  /// Time between repeats while holding an end of the top strip.
  static const repeatMs = 120;
  static Duration repeatEvery(int speed) =>
      Duration(milliseconds: (repeatMs / speedFactor(speed)).round());

  /// Slide distance per step; seeking goes by the speed setting (faster = shorter).
  static double stepPx(
    EdgeZone z, [
    TopEdgeMode top = TopEdgeMode.seek,
    int speed = 3,
  ]) => switch (z) {
    EdgeZone.media =>
      top == TopEdgeMode.seek ? seekStepPx / speedFactor(speed) : trackStepPx,
    EdgeZone.windows => windowStepPx,
    _ => sideStepPx,
  };

  /// How far a movement counts along the zone's axis: up is positive on the side
  /// strips, right is positive on the top strip.
  static double along(EdgeZone z, Offset delta) =>
      z == EdgeZone.media || z == EdgeZone.windows ? delta.dx : -delta.dy;

  /// The key for one step. Codes: 0x8000 | HID consumer usage (see agent/src/hid.rs);
  /// seeking uses the plain Right / Left arrow keys (HID 0x4F / 0x50).
  static int key(
    EdgeZone z, {
    required bool positive,
    TopEdgeMode top = TopEdgeMode.seek,
  }) => switch (z) {
    EdgeZone.volume => positive ? 0x80E9 : 0x80EA, // volume up / down
    EdgeZone.brightness => positive ? 0x806F : 0x8070, // brightness up / down
    EdgeZone.media when top == TopEdgeMode.seek =>
      positive ? 0x4F : 0x50, // right / left arrow
    EdgeZone.media => positive ? 0x80B5 : 0x80B6, // next / previous track
    EdgeZone.windows => 0x2B, // Tab (Shift is added by the caller)
    EdgeZone.none => 0,
  };

  static String label(
    EdgeZone z, {
    required bool positive,
    TopEdgeMode top = TopEdgeMode.seek,
  }) => switch (z) {
    EdgeZone.volume => positive ? 'Volume +' : 'Volume -',
    EdgeZone.brightness => positive ? 'Brightness +' : 'Brightness -',
    EdgeZone.media when top == TopEdgeMode.seek =>
      positive ? 'Forward' : 'Backward',
    EdgeZone.media => positive ? 'Next track' : 'Previous track',
    EdgeZone.windows => positive ? 'Next window' : 'Previous window',
    EdgeZone.none => '',
  };
}

/// Faint markings along the pad's edges that show where the zones are.
class EdgeZoneMarks extends StatelessWidget {
  final TopEdgeMode top;

  /// Whether the computer is thought to be playing: the middle icon then offers pause,
  /// otherwise play.
  final bool playing;

  /// The computer's sound is muted: the volume strip shows a crossed-out speaker.
  final bool muted;

  /// Show the window switcher strip on the bottom edge.
  final bool windows;

  /// The bottom strip switches browser tabs instead of windows.
  final bool tabs;
  const EdgeZoneMarks({
    super.key,
    this.windows = true,
    this.tabs = false,
    this.top = TopEdgeMode.seek,
    this.playing = false,
    this.muted = false,
  });

  static const _c = Colors.white24;

  static Widget _box(IconData icon, double size, Color color) => SizedBox(
    width: EdgeZones.skipHalfWidth,
    child: Icon(icon, size: size, color: color),
  );

  static const _line = Expanded(
    child: Divider(
      color: _c,
      height: 1.5,
      thickness: 1.5,
      indent: 4,
      endIndent: 4,
    ),
  );

  Widget _slider(IconData icon) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('+', style: TextStyle(color: _c, fontSize: 14)),
      Container(width: 1.5, height: 26, color: _c),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Icon(icon, size: 18, color: _c),
      ),
      Container(width: 1.5, height: 26, color: _c),
      const Text('-', style: TextStyle(color: _c, fontSize: 14)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final sideTop = box.maxHeight * EdgeZones.sideTopFraction;
          final sideHeight = box.maxHeight - sideTop;
          return Stack(
            children: [
              Positioned(
                left: 0,
                width: EdgeZones.edge,
                top: sideTop,
                height: sideHeight,
                child: Center(
                  child: _slider(muted ? Icons.volume_off : Icons.volume_up),
                ),
              ),
              Positioned(
                right: 0,
                width: EdgeZones.edge,
                top: sideTop,
                height: sideHeight,
                child: Center(child: _slider(Icons.light_mode)),
              ),
              if (windows)
                Positioned(
                  left: box.maxWidth * EdgeZones.topFrom,
                  right: box.maxWidth * (1 - EdgeZones.topTo),
                  bottom: 0,
                  height: EdgeZones.edge,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.keyboard_double_arrow_left,
                        size: 18,
                        color: _c,
                      ),
                      _line,
                      Icon(
                        tabs ? Icons.tab : Icons.filter_none,
                        size: 18,
                        color: Colors.white38,
                      ),
                      _line,
                      const Icon(
                        Icons.keyboard_double_arrow_right,
                        size: 18,
                        color: _c,
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: box.maxWidth * EdgeZones.topFrom,
                right: box.maxWidth * (1 - EdgeZones.topTo),
                top: 0,
                height: EdgeZones.edge,
                // Each icon sits in a box as wide as its touch area, so the skip buttons
                // (outer boxes) never overlap the seek ends (inner boxes).
                child: Row(
                  children: [
                    if (top == TopEdgeMode.seek)
                      _box(Icons.skip_previous, 22, Colors.white38),
                    _box(
                      top == TopEdgeMode.seek
                          ? Icons.fast_rewind
                          : Icons.skip_previous,
                      18,
                      _c,
                    ),
                    _line,
                    // One icon: play, and after a tap pause (and back).
                    Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      size: 22,
                      color: Colors.white38,
                    ),
                    _line,
                    _box(
                      top == TopEdgeMode.seek
                          ? Icons.fast_forward
                          : Icons.skip_next,
                      18,
                      _c,
                    ),
                    if (top == TopEdgeMode.seek)
                      _box(Icons.skip_next, 22, Colors.white38),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
