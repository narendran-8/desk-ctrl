import 'dart:async';

import 'package:flutter/services.dart';

import 'connection.dart';
import 'scan_screen.dart';

/// Plugging the phone in: the agent sends `deskctrl://pair/TOKEN?usb=1&port=..&name=..` through adb
/// (see agent/src/usb.rs). Android opens this app with it; the computer is added and
/// connected without scanning a QR code.
///
/// Only `usb=1` links are accepted, and they only ever add a link to 127.0.0.1 (the cable's
/// own tunnel), so a stray link from elsewhere cannot point the phone at another computer.
class UsbPairing {
  static const _m = MethodChannel('deskctrl/link');
  static const _events = EventChannel('deskctrl/link/events');
  static StreamSubscription<dynamic>? _sub;

  static Future<void> start() async {
    try {
      _sub ??= _events.receiveBroadcastStream().listen(
        (l) => handle(l as String),
        onError: (_) {},
      );
      final first = await _m.invokeMethod<String>('initialLink');
      if (first != null) await handle(first);
    } catch (_) {
      // Not Android (tests): nothing to listen to.
    }
  }

  static const _cable = EventChannel('deskctrl/usb/state');
  static StreamSubscription<dynamic>? _cableSub;
  static bool? _cableHere;

  /// Listens to Android's USB state: when the cable goes away, the USB link goes at once.
  static void watchCable() {
    try {
      _cableSub ??= _cable.receiveBroadcastStream().listen((v) {
        final here = v == true;
        final was = _cableHere;
        _cableHere = here;
        if (was == true && !here) Connection.instance.cableRemoved();
      }, onError: (_) {});
    } catch (_) {
      // Not Android (tests): nothing to listen to.
    }
  }

  static Future<bool> handle(String link) async {
    final info = PairInfo.parse(link);
    if (info == null || !info.usb) return false;
    await Connection.instance.pairOverUsb(info);
    return true;
  }
}
