import 'package:flutter/services.dart';

/// Controls media on this Android phone, never the connected computer.
class PhoneMedia {
  static const channel = MethodChannel('deskctrl/phone_media');

  static Future<void> action(String name) =>
      channel.invokeMethod('action', name);
  static Future<void> volume(int direction) =>
      channel.invokeMethod('volume', direction);
  static Future<void> mute() => channel.invokeMethod('mute');
  static Future<void> brightness(int direction) =>
      channel.invokeMethod('brightness', direction);
}
