import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'settings.dart';

/// A computer keeps its identifying colour while it stays in the saved list.
/// The first seven use the app's readable accents; additional computers get
/// distinct hues rather than repeating one of those colours.
Color deviceColor(String id) {
  final index = Settings.instance.devices.indexWhere((d) => d.id == id);
  if (index < 0) return Colors.white54;
  if (index < AppTheme.accents.length - 1) return AppTheme.accents[index];
  return HSVColor.fromAHSV(1, (index * 137.508 + 210) % 360, 0.7, 1).toColor();
}
