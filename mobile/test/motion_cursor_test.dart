import 'dart:math' as math;

import 'package:deskctrl/motion_cursor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Where "up" is in the phone's own axes (x right of the screen, y up the screen, z out of it),
  // and where the person looking at the screen has their right hand, for the three ways the
  // phone is held upright.
  const holds = {
    'portrait': (up: (0.0, 1.0, 0.0), right: (1.0, 0.0, 0.0)),
    'landscape, top to the left': (
      up: (1.0, 0.0, 0.0),
      right: (0.0, -1.0, 0.0),
    ),
    'landscape, top to the right': (
      up: (-1.0, 0.0, 0.0),
      right: (0.0, 1.0, 0.0),
    ),
  };

  /// Gravity as the accelerometer reads it when the phone is upright, tilted by [lean] radians to
  /// its right and by [back] radians with the top of the screen away from the person.
  void feed(
    MotionCursor m,
    ({(double, double, double) up, (double, double, double) right}) h, {
    double lean = 0,
    double back = 0,
  }) {
    final u = h.up, r = h.right;
    final c = math.cos(back), s = math.sin(back);
    final x = (u.$1 * c + r.$1 * math.sin(lean)) * 9.8;
    final y = (u.$2 * c + r.$2 * math.sin(lean)) * 9.8;
    final z = s * 9.8;
    for (var i = 0; i < 30; i++) {
      m.gravity(x, y, z);
    }
  }

  group(
    'the same tilt gives the same cursor movement however the phone is held',
    () {
      for (final e in holds.entries) {
        test(e.key, () {
          final m = MotionCursor();
          feed(m, e.value);
          expect(m.engage(), isTrue);
          expect(
            m.move(0.01)!.dx.abs() + m.move(0.01)!.dy.abs(),
            0,
            reason: 'at rest: nothing',
          );

          feed(m, e.value, lean: 0.3);
          final right = m.move(0.01)!;
          expect(
            right.dx,
            greaterThan(1),
            reason: 'leaning right: ${right.dx}',
          );
          expect(right.dy.abs(), lessThan(0.01));

          feed(m, e.value, lean: -0.3);
          expect(m.move(0.01)!.dx, closeTo(-right.dx, 0.01));

          feed(m, e.value, back: 0.3); // the top of the screen away: up
          final up = m.move(0.01)!;
          expect(up.dy, lessThan(-1), reason: 'tilted back: ${up.dy}');
          expect(up.dx.abs(), lessThan(0.01));

          feed(m, e.value, back: -0.3);
          expect(m.move(0.01)!.dy, closeTo(-up.dy, 0.01));
        });
      }
    },
  );

  test(
    'a little tilt does nothing; more tilt is faster than proportionally',
    () {
      final m = MotionCursor();
      final h = holds['portrait']!;
      feed(m, h);
      m.engage();
      feed(m, h, lean: 0.03);
      expect(m.move(0.01)!.dx, 0, reason: 'inside the dead zone');
      feed(m, h, lean: 0.2);
      final small = m.move(0.01)!.dx;
      feed(m, h, lean: 0.4);
      expect(m.move(0.01)!.dx, greaterThan(small * 2));
    },
  );

  test('speed and invert', () {
    final m = MotionCursor();
    final h = holds['portrait']!;
    feed(m, h);
    m.engage();
    feed(m, h, lean: 0.3);
    final normal = m.move(0.01)!.dx;
    expect(m.move(0.01, speed: 1800)!.dx, closeTo(normal * 2, 0.001));
    expect(m.move(0.01, invert: true)!.dx, closeTo(-normal, 0.001));
  });

  test('nothing moves before the clutch is engaged, or lying flat', () {
    final m = MotionCursor();
    expect(m.engage(), isFalse, reason: 'no reading yet');
    expect(m.move(0.01), isNull);
    for (var i = 0; i < 30; i++) {
      m.gravity(0, 0, 9.8); // flat on a table
    }
    expect(m.engage(), isFalse);
    expect(m.move(0.01), isNull);
  });

  test('following: a tilt that is kept up fades away', () {
    final m = MotionCursor();
    final h = holds['portrait']!;
    feed(m, h);
    m.engage();
    feed(m, h, lean: 0.3);
    final first = m.move(0.01, follow: true)!.dx;
    expect(first, greaterThan(1));
    var last = first;
    for (var i = 0; i < 400; i++) {
      last = m.move(0.01, follow: true)!.dx; // 4 seconds
    }
    expect(last, lessThan(first / 4));
  });
}
