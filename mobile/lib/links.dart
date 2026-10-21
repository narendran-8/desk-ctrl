import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum Transport { wifi, bluetooth, usb }

enum LinkState { disconnected, connecting, connected }

extension TransportInfo on Transport {
  String get label => switch (this) {
    Transport.wifi => 'Wi-Fi',
    Transport.bluetooth => 'Bluetooth',
    Transport.usb => 'USB',
  };
}

/// One way of reaching the desktop agent. Both kinds carry the same payloads
/// (see agent/src/hid.rs); a link is "connected" only after the agent has
/// accepted our token and answered.
abstract class Link extends ChangeNotifier {
  Link(this.transport);

  final Transport transport;
  LinkState state = LinkState.disconnected;
  String? error;

  /// Called when an established link drops on its own (not after close() or a failed open()).
  VoidCallback? onLost;

  /// Lock-key lights reported by the computer: bit0 Caps, bit1 Num, bit2 Scroll.
  void Function(int flags)? onLeds;

  static const ledFrame = 0x10;

  /// Volume / brightness percentages reported by the computer: [volume, brightness, muted],
  /// 255 meaning unknown.
  void Function(int volume, int brightness, bool muted)? onLevels;

  static const levelFrame = 0x12;

  /// The computer says a text field just got the keyboard focus.
  /// The argument says whether it can be typed into (older agents send only "yes").
  void Function(bool typeable)? onTextFocus;

  static const focusFrame = 0x13;

  /// A piece of the computer's answer to the voice screen: `[0x15, last, ...json bytes]`.
  void Function(Uint8List frame)? onVoice;

  static const voiceFrame = 0x15;

  /// How the computer can be reached by Wi-Fi and Bluetooth: `id=..&ip=..&port=..&bt=..&name=..`.
  /// Only sent, and only accepted, on the USB cable.
  void Function(String info)? onInfo;

  static const infoFrame = 0x14;

  /// Bumped by every open()/close() so callbacks from an older attempt are ignored.
  int _epoch = 0;

  bool get connected => state == LinkState.connected;

  /// Sent to the desktop every second so it can tell this link is alive. It ignores the content.
  static const keepaliveFrame = 0x00;

  /// Sent by the desktop every second. Any message from it counts as a sign of life.
  static const heartbeatFrame = 0x11;

  /// A link that hears nothing from the desktop for this long is declared dead, so
  /// traffic moves to the other link instead of vanishing into a link that is down
  /// (Wi-Fi switched off, out of Bluetooth range ...) while it still looks connected.
  @visibleForTesting
  static Duration deadAfter = const Duration(milliseconds: 3500);

  DateTime _lastRx = DateTime.now();
  Timer? _watchdog;
  int _beat = 0;

  /// Whether this desktop has sent a heartbeat on this link. An older agent sends none,
  /// so a link is only declared dead once the desktop has shown it sends them.
  bool _heartbeats = false;

  /// Call for everything received from the desktop.
  void markAlive() => _lastRx = DateTime.now();

  /// Call when the desktop's heartbeat frame arrives.
  void markHeartbeat() {
    _heartbeats = true;
    markAlive();
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _lastRx = DateTime.now();
    _beat = 0;
    _heartbeats = false;
    _watchdog = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (state != LinkState.connected) return;
      if (_heartbeats && DateTime.now().difference(_lastRx) > deadAfter) {
        declareDead();
        return;
      }
      _beat++;
      if (_beat.isOdd) send(Uint8List.fromList([keepaliveFrame]));
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// No sign of life from the desktop: drop this link and tell the owner.
  @protected
  void declareDead();

  /// Completes true once the desktop accepted our token. Never throws: on
  /// failure it completes false and sets [error].
  Future<bool> open();

  /// Sends one protocol payload (no framing).
  void send(Uint8List payload);

  Future<void> close();

  void setState(LinkState s, [String? err]) {
    state = s;
    error = err;
    s == LinkState.connected ? _startWatchdog() : _stopWatchdog();
    notifyListeners();
  }

  static String describe(Object e) {
    if (e is String) return e;
    if (e is TimeoutException) return 'Timed out';
    if (e is PlatformException) return e.message ?? e.code;
    return e.toString().replaceFirst('Exception: ', '');
  }
}

class WifiLink extends Link {
  WifiLink() : super(Transport.wifi);

  /// For [UsbLink].
  WifiLink._(super.transport);

  String host = '';
  int port = 8765;
  String token = '';

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;

  @override
  Future<bool> open() async {
    final epoch = ++_epoch;
    await _drop();
    setState(LinkState.connecting);
    try {
      final ch = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
      _ch = ch;
      await ch.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw transport == Transport.usb
            ? 'Timed out - is the phone plugged in with USB debugging on?'
            : 'Timed out - is the agent running at $host:$port?',
      );
      if (epoch != _epoch) return false;

      final ack = Completer<void>();
      ack.future.ignore();
      _sub = ch.stream.listen(
        (m) {
          markAlive();
          if (m is List<int> && m.length == 1 && m[0] == Link.heartbeatFrame) {
            markHeartbeat();
            return;
          }
          if (transport == Transport.usb &&
              m is List<int> &&
              m.length > 1 &&
              m[0] == Link.infoFrame) {
            if (ack.isCompleted)
              onInfo?.call(utf8.decode(m.sublist(1), allowMalformed: true));
            return;
          }
          if (m is List<int> && m.length >= 2 && m[0] == Link.voiceFrame) {
            if (ack.isCompleted) onVoice?.call(Uint8List.fromList(m));
            return;
          }
          if (m is List<int> &&
              (m.length == 1 || m.length == 2) &&
              m[0] == Link.focusFrame) {
            if (ack.isCompleted) onTextFocus?.call(m.length == 1 || m[1] != 0);
            return;
          }
          if (!ack.isCompleted) {
            ack.complete(); // the first message is the "ok"
          } else if (m is List<int> && m.length >= 2 && m[0] == Link.ledFrame) {
            onLeds?.call(m[1]);
          } else if (m is List<int> &&
              m.length >= 4 &&
              m[0] == Link.levelFrame) {
            onLevels?.call(m[1], m[2], m[3] != 0);
          }
        },
        onDone: () => _ended(epoch, ack, 'Connection closed - wrong token?'),
        onError: (_) => _ended(
          epoch,
          ack,
          transport == Transport.usb
              ? 'USB cable not connected'
              : 'Connection error',
        ),
      );
      ch.sink.add(token);
      await ack.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () =>
            throw 'No reply from the agent - is it the latest version?',
      );
      if (epoch != _epoch) return false;
      setState(LinkState.connected);
      return true;
    } catch (e) {
      if (epoch == _epoch) {
        await _drop();
        setState(LinkState.disconnected, Link.describe(e));
      }
      return false;
    }
  }

  void _ended(int epoch, Completer<void> ack, String why) {
    if (epoch != _epoch) return;
    if (!ack.isCompleted) {
      ack.completeError(why); // open() reports it
      return;
    }
    _epoch++;
    _drop();
    setState(LinkState.disconnected, why);
    onLost?.call();
  }

  @override
  void declareDead() {
    _epoch++;
    _drop();
    setState(LinkState.disconnected, 'No response from the PC');
    onLost?.call();
  }

  @override
  void send(Uint8List payload) {
    if (state == LinkState.connected) _ch?.sink.add(payload);
  }

  Future<void> _drop() async {
    await _sub?.cancel();
    _sub = null;
    final ch = _ch;
    _ch = null;
    // Do not await: closing a socket that never connected can wait forever, which
    // would leave an attempt to reach a switched-off computer stuck on "Connecting".
    ch?.sink.close().catchError((_) {});
  }

  @override
  Future<void> close() async {
    _epoch++;
    await _drop();
    setState(LinkState.disconnected);
  }
}

/// The USB cable. The agent runs `adb reverse`, which makes port [port] on the phone's own
/// localhost lead to the agent on the computer, so this is the Wi-Fi link pointed at
/// 127.0.0.1: same protocol, same token, no network needed.
class UsbLink extends WifiLink {
  UsbLink() : super._(Transport.usb) {
    host = '127.0.0.1';
  }

  /// Android says the data cable is gone: do not wait for the heartbeat watchdog (or for a
  /// tunnel that never closes), move to the other link now.
  void cableRemoved() {
    if (connected) declareDead();
  }
}

class BtDevice {
  final String name;
  final String address;
  const BtDevice(this.name, this.address);
}

/// Bluetooth Classic RFCOMM through the Kotlin bridge in MainActivity.kt.
/// RFCOMM is a byte stream, so every payload is sent as `[len][payload]`.
class BtLink extends Link {
  BtLink() : super(Transport.bluetooth);

  static const _m = MethodChannel('deskctrl/bt');
  static const _events = EventChannel('deskctrl/bt/events');
  static const _ack = 0x06;

  /// Open Bluetooth links by PC address; native events carry that address.
  static final Map<String, BtLink> _open = {};
  static StreamSubscription<dynamic>? _eventSub;

  static void _dispatch(dynamic event) {
    final e = event as Map;
    _open[e['id'] as String]?._onEvent(e);
  }

  String address = '';
  String token = '';

  String? _registered; // address this link is registered under
  Completer<void>? _acked;
  final List<int> _buf = [];

  static Future<bool> ensurePermission() async =>
      await _m.invokeMethod<bool>('ensurePermission') ?? false;

  static Future<List<BtDevice>> bondedDevices() async {
    final list =
        await _m.invokeMethod<List<dynamic>>('bondedDevices') ?? const [];
    return [
      for (final d in list)
        BtDevice((d as Map)['name'] as String, d['address'] as String),
    ];
  }

  static Uint8List _frame(List<int> payload) =>
      Uint8List.fromList([payload.length, ...payload]);

  @override
  Future<bool> open() async {
    final epoch = ++_epoch;
    await _drop();
    setState(LinkState.connecting);
    try {
      if (address.isEmpty) throw 'No Bluetooth device chosen';
      if (!await ensurePermission()) throw 'Bluetooth permission denied';
      _eventSub ??= _events.receiveBroadcastStream().listen(
        _dispatch,
        onError: (_) {},
      );
      _open[address] = this;
      _registered = address;
      _buf.clear();
      final acked = _acked = Completer<void>();
      acked.future.ignore();
      await _m
          .invokeMethod('connect', {'address': address})
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw 'Timed out connecting',
          );
      if (epoch != _epoch) return false;

      await _write(_frame(token.codeUnits));
      await acked.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => throw 'No reply from the agent - wrong token?',
      );
      if (epoch != _epoch) return false;
      setState(LinkState.connected);
      return true;
    } catch (e) {
      if (epoch == _epoch) {
        await _drop();
        setState(LinkState.disconnected, friendly(Link.describe(e)));
      }
      return false;
    }
  }

  /// What to show for a failed Bluetooth connection: a hint, plus the system's own
  /// message in brackets so the real reason is never hidden.
  @visibleForTesting
  static String friendly(String m) {
    if (m.contains('read failed') ||
        m.contains('Service discovery failed') ||
        m.contains('refused')) {
      return 'Could not reach the PC over Bluetooth. Check that the agent is running on it '
          'and that it is paired with this phone. ($m)';
    }
    return m;
  }

  @override
  void declareDead() {
    _epoch++;
    _drop();
    setState(LinkState.disconnected, 'No response from the PC');
    onLost?.call();
  }

  void _onEvent(Map e) {
    if (e['t'] == 'data') {
      markAlive();
      _buf.addAll(e['b'] as Uint8List);
      while (_buf.isNotEmpty) {
        final len = _buf[0];
        if (len == 0) {
          _buf.removeAt(0);
        } else if (_buf.length >= 1 + len) {
          final payload = _buf.sublist(1, 1 + len);
          _buf.removeRange(0, 1 + len);
          if (payload.first == _ack) {
            if (!(_acked?.isCompleted ?? true)) _acked!.complete();
          } else if (payload.first == Link.heartbeatFrame) {
            markHeartbeat();
          } else if (payload.first == Link.ledFrame && payload.length >= 2) {
            onLeds?.call(payload[1]);
          } else if (payload.first == Link.voiceFrame && payload.length >= 2) {
            onVoice?.call(Uint8List.fromList(payload));
          } else if (payload.first == Link.focusFrame) {
            onTextFocus?.call(payload.length == 1 || payload[1] != 0);
          } else if (payload.first == Link.levelFrame && payload.length >= 4) {
            onLevels?.call(payload[1], payload[2], payload[3] != 0);
          }
        } else {
          break;
        }
      }
    } else if (e['t'] == 'closed') {
      if (state == LinkState.connecting) {
        final a = _acked;
        if (a != null && !a.isCompleted) {
          a.completeError('Connection closed by the PC - wrong token?');
        }
      } else if (state == LinkState.connected) {
        _epoch++;
        setState(LinkState.disconnected, 'Bluetooth link lost');
        onLost?.call();
      }
    }
  }

  @override
  void send(Uint8List payload) {
    if (state != LinkState.connected) return;
    _write(_frame(payload)).catchError((_) {});
  }

  Future<void> _write(Uint8List framed) =>
      _m.invokeMethod('write', {'address': address, 'bytes': framed});

  Future<void> _drop() async {
    final a = _registered;
    if (a == null) return;
    _registered = null;
    if (_open[a] == this) _open.remove(a);
    try {
      await _m.invokeMethod('disconnect', {'address': a});
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    _epoch++;
    await _drop();
    setState(LinkState.disconnected);
  }
}
