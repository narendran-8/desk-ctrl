import 'dart:ui';

import 'package:deskctrl/edge_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pad = Size(700, 300);

  test('which zone a touch falls into', () {
    expect(
      EdgeZones.at(const Offset(350, 150), pad),
      EdgeZone.none,
      reason: 'the middle is the normal pad',
    );
    expect(
      EdgeZones.at(const Offset(10, 200), pad),
      EdgeZone.volume,
      reason: 'left edge',
    );
    expect(
      EdgeZones.at(const Offset(690, 200), pad),
      EdgeZone.brightness,
      reason: 'right edge',
    );
    expect(
      EdgeZones.at(const Offset(350, 10), pad),
      EdgeZone.media,
      reason: 'top edge, middle',
    );
  });

  test('the top-right corner and the on/off button corner are left alone', () {
    expect(
      EdgeZones.at(const Offset(680, 10), pad),
      EdgeZone.none,
      reason: 'top-right: no zone (that icon is not used)',
    );
    expect(
      EdgeZones.at(const Offset(20, 10), pad),
      EdgeZone.none,
      reason: 'top-left: the touchpad on/off button',
    );
    expect(
      EdgeZones.at(const Offset(10, 40), pad),
      EdgeZone.none,
      reason: 'side strips start below the top band',
    );
    expect(
      EdgeZones.at(const Offset(100, 10), pad),
      EdgeZone.none,
      reason: 'top strip covers only the middle',
    );
  });

  test('slides map to the right keys', () {
    // Up on a side strip is "more", right on the top strip is "forward".
    expect(EdgeZones.along(EdgeZone.volume, const Offset(0, -30)), 30);
    expect(EdgeZones.along(EdgeZone.brightness, const Offset(0, 30)), -30);
    expect(EdgeZones.along(EdgeZone.media, const Offset(30, 0)), 30);

    expect(EdgeZones.key(EdgeZone.volume, positive: true), 0x80E9);
    expect(EdgeZones.key(EdgeZone.volume, positive: false), 0x80EA);
    expect(EdgeZones.key(EdgeZone.brightness, positive: true), 0x806F);
    expect(EdgeZones.key(EdgeZone.brightness, positive: false), 0x8070);
  });

  test(
    'the top edge seeks forward / backward by default (Right / Left arrow)',
    () {
      expect(
        EdgeZones.key(EdgeZone.media, positive: true),
        0x4F,
        reason: 'right = forward',
      );
      expect(
        EdgeZones.key(EdgeZone.media, positive: false),
        0x50,
        reason: 'left = backward',
      );
      expect(EdgeZones.label(EdgeZone.media, positive: true), 'Forward');
      expect(EdgeZones.label(EdgeZone.media, positive: false), 'Backward');
    },
  );

  test('the top edge can skip tracks instead', () {
    expect(
      EdgeZones.key(EdgeZone.media, positive: true, top: TopEdgeMode.track),
      0x80B5,
    );
    expect(
      EdgeZones.key(EdgeZone.media, positive: false, top: TopEdgeMode.track),
      0x80B6,
    );
    expect(
      EdgeZones.label(EdgeZone.media, positive: true, top: TopEdgeMode.track),
      'Next track',
    );
    expect(parseTopEdgeMode('track'), TopEdgeMode.track);
    expect(parseTopEdgeMode('seek'), TopEdgeMode.seek);
    expect(
      parseTopEdgeMode('nonsense'),
      TopEdgeMode.seek,
      reason: 'unknown values fall back to seek',
    );
  });

  test('the middle of the top strip is the play / pause icon', () {
    expect(
      EdgeZones.isPlayPause(const Offset(350, 10), pad),
      isTrue,
      reason: 'dead centre',
    );
    expect(
      EdgeZones.isPlayPause(const Offset(380, 20), pad),
      isTrue,
      reason: 'a little off centre',
    );
    expect(
      EdgeZones.isPlayPause(const Offset(450, 10), pad),
      isFalse,
      reason: 'elsewhere on the strip',
    );
    expect(
      EdgeZones.isPlayPause(const Offset(350, 150), pad),
      isFalse,
      reason: 'not on the top strip',
    );
    expect(EdgeZones.playPauseKey, 0x80CD);
  });

  test('the seek speed setting changes the repeat rate and the slide step', () {
    expect(EdgeZones.repeatEvery(3), const Duration(milliseconds: 120));
    expect(
      EdgeZones.repeatEvery(5) < EdgeZones.repeatEvery(3),
      isTrue,
      reason: 'fast repeats sooner',
    );
    expect(EdgeZones.repeatEvery(1) > EdgeZones.repeatEvery(3), isTrue);
    expect(EdgeZones.stepPx(EdgeZone.media, TopEdgeMode.seek, 3), 60);
    expect(
      EdgeZones.stepPx(EdgeZone.media, TopEdgeMode.seek, 5) < 60,
      isTrue,
      reason: 'fast = less sliding per step',
    );
    expect(EdgeZones.stepPx(EdgeZone.media, TopEdgeMode.seek, 1) > 60, isTrue);
    expect(EdgeZones.stepPx(EdgeZone.media, TopEdgeMode.track, 5), 80);
    expect(EdgeZones.stepPx(EdgeZone.volume, TopEdgeMode.seek, 5), 22);
  });
}
