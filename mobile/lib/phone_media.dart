import 'package:flutter/services.dart';

/// Controls media on this Android phone, never the connected computer.
class PhoneMedia {
  static const channel = MethodChannel('deskctrl/phone_media');

  static Future<void> action(String name) =>
      channel.invokeMethod('action', name);
  static Future<int?> volume(int direction) =>
      channel.invokeMethod<int>('volume', direction);
  static Future<void> mute() => channel.invokeMethod('mute');
  static Future<int?> brightness(int direction) =>
      channel.invokeMethod<int>('brightness', direction);
}
