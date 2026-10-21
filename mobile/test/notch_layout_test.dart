import 'package:deskctrl/notch_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // This phone: 820 x 360 dp in landscape, notch 51 dp tall at y 154..205 on the side edge.
  test('landscape rail: three icons above the notch, three below', () {
    expect(
      iconsBeforeNotch(n: 6, length: 360, cutout: (154, 205), extent: 48),
      3,
    );
  });

  // Portrait: 360 dp wide, notch 51 dp wide at x 154..205 on the top edge.
  test('portrait strip: three icons left of the notch, three right of it', () {
    expect(
      iconsBeforeNotch(n: 6, length: 360, cutout: (154, 205), extent: 48),
      3,
    );
  });

  test('no notch: everything in one group', () {
    expect(iconsBeforeNotch(n: 6, length: 360, cutout: null, extent: 48), 6);
  });

  test('notch near the start: icons move to the roomy side', () {
    // Only 60 dp before the notch (1 icon), 250 dp after it (5 icons).
    expect(
      iconsBeforeNotch(n: 6, length: 360, cutout: (60, 110), extent: 48),
      1,
    );
  });

  test('never puts an icon where the notch is', () {
    for (var start = 0.0; start <= 300; start += 7) {
      final cut = (start, start + 51);
      for (var n = 1; n <= 6; n++) {
        final before = iconsBeforeNotch(
          n: n,
          length: 360,
          cutout: cut,
          extent: 48,
        );
        expect(
          before * 48 <= start + 0.001,
          isTrue,
          reason: 'n=$n cut=$cut before=$before overlaps',
        );
        final after = n - before;
        // After the notch there is either room for them, or nothing fits anyway.
        if (before >= ((start - 2) / 48).floor().clamp(0, n)) continue;
        expect(
          after * 48 <= 360 - (start + 51) + 0.001,
          isTrue,
          reason: 'n=$n cut=$cut after=$after overlaps',
        );
      }
    }
  });

  group(
    'planNotchBar: wide notches shrink the icons, then use a second line',
    () {
      test('no notch: full size, one line', () {
        final p = planNotchBar(n: 6, length: 360, cutout: null);
        expect((p.extent, p.before, p.second), (48.0, 6, 0));
      });

      test('a small hole: full size', () {
        final p = planNotchBar(n: 5, length: 360, cutout: (168, 192));
        expect(p.extent, 48.0);
        expect(p.second, 0);
      });

      test('a wide notch: smaller icons so that all five fit around it', () {
        final p = planNotchBar(n: 5, length: 360, cutout: (115, 245));
        expect(p.extent, lessThan(48.0));
        expect(p.extent, greaterThanOrEqualTo(36.0));
        expect(p.second, 0);
        expect(p.before * p.extent, lessThanOrEqualTo(115));
        expect((5 - p.before) * p.extent, lessThanOrEqualTo(360 - 245));
      });

      test('a very wide notch: what does not fit goes on a second line', () {
        final p = planNotchBar(n: 5, length: 360, cutout: (80, 280));
        expect(p.extent, 36.0);
        expect(p.second, 1);
        expect(p.before, 2);
      });

      test('whatever the notch, the first line never reaches it', () {
        for (var start = 0.0; start <= 320; start += 11) {
          for (final width in [20.0, 60.0, 130.0, 200.0]) {
            if (start + width > 360) continue; // a notch is on the screen
            for (var n = 1; n <= 6; n++) {
              final p = planNotchBar(
                n: n,
                length: 360,
                cutout: (start, start + width),
              );
              final first = n - p.second;
              final after = first - p.before;
              expect(
                p.before * p.extent <= start + 2.001,
                isTrue,
                reason: 'n $n at $start +$width: $p',
              );
              expect(
                after * p.extent <= 360 - (start + width) + 2.001,
                isTrue,
                reason: 'n $n at $start +$width: $p',
              );
              expect(
                p.second >= 0 && p.before >= 0 && p.before <= first,
                isTrue,
                reason: '$p',
              );
            }
          }
        }
      });
    },
  );
}
