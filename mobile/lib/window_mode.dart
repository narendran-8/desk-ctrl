import 'package:flutter/services.dart';

/// Window options that need the Android side.
class WindowMode {
  static const _channel = MethodChannel('deskctrl/window');

  /// Draw into the notch / camera cut-out area (true) or stay out of it (false).
  static Future<void> useCutout(bool on) async {
    try {
      await _channel.invokeMethod('setCutout', on);
    } catch (_) {
      // Not Android, or an old version: nothing to do.
    }
  }

  /// Screen brightness of this app's window: 0 = the system's own setting, else 0.01 ... 1.
  static Future<void> setBrightness(double level) async {
    try {
      await _channel.invokeMethod('setBrightness', level);
    } catch (_) {
      // Not Android, or an old version: nothing to do.
    }
  }
}
