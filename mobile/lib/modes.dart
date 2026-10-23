import 'package:flutter/material.dart';

/// The screens the phone can show. The keyboard is always available.
enum Mode { keyboard, mouse, pad, voice, mobile }

extension ModeInfo on Mode {
  IconData get icon => switch (this) {
    Mode.keyboard => Icons.keyboard,
    Mode.mouse => Icons.mouse,
    Mode.pad => Icons.touch_app,
    Mode.voice => Icons.mic,
    Mode.mobile => Icons.smartphone,
  };

  String get label => switch (this) {
    Mode.keyboard => 'Keyboard',
    Mode.mouse => 'Mouse',
    Mode.pad => 'Trackpad',
    Mode.voice => 'Voice',
    Mode.mobile => 'Mobile',
  };
}

/// Initial mode order; users can rearrange it in Settings.
const defaultModeOrder = [
  Mode.keyboard,
  Mode.mouse,
  Mode.pad,
  Mode.voice,
  Mode.mobile,
];

/// [order] with any mode it lacks added at the end, so a mode is never lost.
List<Mode> completeOrder(List<Mode> order) => [
  ...order,
  for (final m in Mode.values)
    if (!order.contains(m)) m,
];

/// The tabs to offer, in the user's order, given what is enabled in Settings.
List<Mode> availableModes({
  required bool mouse,
  required bool pad,
  bool voice = false,
  bool mobile = false,
  List<Mode> order = defaultModeOrder,
}) => [
  for (final m in completeOrder(order))
    if (m == Mode.keyboard ||
        (m == Mode.mouse && mouse) ||
        (m == Mode.pad && pad) ||
        (m == Mode.voice && voice) ||
        (m == Mode.mobile && mobile))
      m,
];

/// The mode a tap on the mode button moves to (wraps around).
Mode nextMode(List<Mode> modes, Mode current) {
  final i = modes.indexOf(current);
  return modes[(i + 1) % modes.length];
}

/// Parse the saved order; unknown names are ignored.
List<Mode> parseModeOrder(List<String> names) => [
  for (final n in names)
    for (final m in Mode.values)
      if (m.name == n) m,
];
