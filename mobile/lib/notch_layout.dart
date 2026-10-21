import 'dart:math' as math;

/// How many of [n] icons go in front of a notch, with the rest after it.
///
/// [length] is the size of the bar along its axis and [cutout] where the notch
/// starts and ends along that axis (null: no notch, everything goes in front).
/// Icons are split evenly, limited by how many fit on each side of the notch.
int iconsBeforeNotch({
  required int n,
  required double length,
  required (double, double)? cutout,
  required double extent,
  double margin = 2,
}) {
  if (cutout == null) return n;
  final capBefore = ((cutout.$1 - margin) / extent).floor().clamp(0, n);
  final capAfter = ((length - cutout.$2 - margin) / extent).floor().clamp(0, n);
  final lo = math.max(0, n - capAfter);
  return lo <= capBefore ? ((n + 1) ~/ 2).clamp(lo, capBefore) : capBefore;
}

/// How the icons of the bar are placed around the notch.
class NotchPlan {
  /// Size of one icon cell along the bar.
  final double extent;

  /// Icons in front of the notch on the first line; the rest of that line goes after it.
  final int before;

  /// Icons that did not fit around the notch even at the smallest size: they go on a second line
  /// (after the notch's depth), where the whole length is free.
  final int second;
  const NotchPlan(this.extent, this.before, this.second);

  @override
  String toString() =>
      'NotchPlan(extent $extent, before $before, second $second)';
}

/// Places [n] icons along a bar of [length] around a notch at [cutout] (start, end along the bar).
/// The icons are as big as [extent] when they fit; around a wide notch they shrink step by step
/// down to [minExtent]; if even that is too small for all of them, the rest go on a second line.
/// No icon ever lies where the notch is.
NotchPlan planNotchBar({
  required int n,
  required double length,
  required (double, double)? cutout,
  double extent = 48,
  double minExtent = 36,
  double margin = 2,
}) {
  if (cutout == null) return NotchPlan(extent, n, 0);
  for (var e = extent; e >= minExtent - 0.001; e -= 4) {
    final capBefore = ((cutout.$1 - margin) / e).floor().clamp(0, n);
    final capAfter = ((length - cutout.$2 - margin) / e).floor().clamp(0, n);
    if (capBefore + capAfter >= n) {
      return NotchPlan(
        e,
        iconsBeforeNotch(
          n: n,
          length: length,
          cutout: cutout,
          extent: e,
          margin: margin,
        ),
        0,
      );
    }
  }
  final capBefore = ((cutout.$1 - margin) / minExtent).floor().clamp(0, n);
  final capAfter = ((length - cutout.$2 - margin) / minExtent).floor().clamp(
    0,
    n,
  );
  final first = capBefore + capAfter;
  return NotchPlan(minExtent, math.min(capBefore, first), n - first);
}
