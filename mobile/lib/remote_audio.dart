import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'connection.dart';
import 'settings.dart';

enum RemoteAudioPhase { idle, discovering, connecting, active, error }

class RemoteAudioDestination {
  const RemoteAudioDestination({
    required this.key,
    required this.computerId,
    required this.computerName,
    required this.outputId,
    required this.outputName,
    this.phone = false,
  });

  final String key;
  final String computerId;
  final String computerName;
  final String outputId;
  final String outputName;
  final bool phone;

  String get label => phone ? 'This phone' : '$computerName — $outputName';
}

class _Endpoint {
  const _Endpoint(this.url, this.token);
  final String url;
  final String token;
}

class _AudioSocket {
  _AudioSocket._(this.socket, this.text, this.binary, this.closed);
  final WebSocket socket;
  final Stream<String> text;
  final Stream<Uint8List> binary;
  final Future<void> closed;

  static Future<_AudioSocket> open(_Endpoint endpoint) async {
    final ws = await WebSocket.connect(endpoint.url)
        .timeout(const Duration(seconds: 5));
    final text = StreamController<String>.broadcast(sync: true);
    final binary = StreamController<Uint8List>.broadcast(sync: true);
    final accepted = Completer<void>();
    final done = Completer<void>();
    var authenticated = false;
    ws.listen(
      (message) {
        if (!authenticated) {
          if (message == 'ok') {
            authenticated = true;
            accepted.complete();
          }
          return;
        }
        if (message is String) text.add(message);
        if (message is List<int>) binary.add(Uint8List.fromList(message));
      },
      onError: (Object e, StackTrace st) {
        if (!accepted.isCompleted) accepted.completeError(e, st);
        text.addError(e, st);
        binary.addError(e, st);
      },
      onDone: () {
        if (!accepted.isCompleted) {
          accepted.completeError('Agent rejected the audio connection');
        }
        if (!done.isCompleted) done.complete();
        text.close();
        binary.close();
      },
      cancelOnError: false,
    );
    ws.add(endpoint.token);
    await accepted.future.timeout(const Duration(seconds: 4));
    return _AudioSocket._(ws, text.stream, binary.stream, done.future);
  }

  Future<Map<String, dynamic>> command(Map<String, Object?> value) async {
    final answer = text.first.timeout(const Duration(seconds: 6));
    socket.add(jsonEncode(value));
    final decoded = jsonDecode(await answer) as Map<String, dynamic>;
    if (decoded['op'] == 'error') throw decoded['message'] ?? 'Audio error';
    return decoded;
  }

  Future<void> close() async {
    try {
      socket.add(jsonEncode({'op': 'stop'}));
    } catch (_) {}
    await socket.close().timeout(const Duration(seconds: 2), onTimeout: () {});
  }
}

class RemoteAudio extends ChangeNotifier {
  RemoteAudio._() {
    Connection.instance.addListener(_connectionChanged);
  }
  static final RemoteAudio instance = RemoteAudio._();
  static const _native = MethodChannel('deskctrl/remote_audio');

  RemoteAudioPhase phase = RemoteAudioPhase.idle;
  String? message;
  List<RemoteAudioDestination> destinations = const [];
  String selected = 'phone';
  bool muted = false;
  double volume = 1;

  String? _sourceId;
  String? _sourceUrl;
  String? _destinationUrl;
  _AudioSocket? _source;
  _AudioSocket? _sink;
  StreamSubscription<Uint8List>? _audioSub;
  bool _closing = false;
  Timer? _reconnect;

  bool get active => phase == RemoteAudioPhase.active;

  void select(String key) {
    if (active || !destinations.any((d) => d.key == key)) {
      return;
    }
    selected = key;
    notifyListeners();
  }

  _Endpoint? _endpoint(String deviceId) {
    final session = Connection.instance.connectedSession(deviceId);
    if (session == null) return null;
    final d = session.device;
    if (session.usb.connected) {
      return _Endpoint('ws://127.0.0.1:${d.port}/audio/v1', d.token);
    }
    if (session.wifi.connected && d.host.isNotEmpty) {
      return _Endpoint('ws://${d.host}:${d.port}/audio/v1', d.token);
    }
    return null; // the control RFCOMM frame is deliberately too small for audio
  }

  Future<void> discover() async {
    if (!Settings.instance.remoteAudioEnabled) return;
    phase = RemoteAudioPhase.discovering;
    message = null;
    notifyListeners();
    final sourceId = Connection.instance.activeId;
    final found = <RemoteAudioDestination>[
      const RemoteAudioDestination(
        key: 'phone',
        computerId: '',
        computerName: '',
        outputId: 'android',
        outputName: 'Android media output',
        phone: true,
      ),
    ];
    for (final id in Connection.instance.connectedDeviceIds) {
      if (id == sourceId) continue;
      final endpoint = _endpoint(id);
      if (endpoint == null) continue;
      _AudioSocket? socket;
      try {
        socket = await _AudioSocket.open(endpoint);
        final info = await socket.command({'op': 'discover'});
        for (final raw in (info['outputs'] as List<dynamic>? ?? const [])) {
          final output = raw as Map<dynamic, dynamic>;
          final outputId = output['id'] as String;
          found.add(
            RemoteAudioDestination(
              key: '$id|$outputId',
              computerId: id,
              computerName:
                  info['name'] as String? ??
                  Settings.instance.deviceById(id)?.title ??
                  'Computer',
              outputId: outputId,
              outputName: output['label'] as String? ?? outputId,
            ),
          );
        }
      } catch (_) {
        // One unavailable computer must not hide the phone or the other destinations.
      } finally {
        await socket?.close();
      }
    }
    destinations = found;
    final remembered = Settings.instance.remoteAudioLastDestination;
    selected = found.any((d) => d.key == remembered) ? remembered : 'phone';
    phase = RemoteAudioPhase.idle;
    notifyListeners();
  }

  Future<void> start() async {
    if (phase == RemoteAudioPhase.connecting || active) return;
    final sourceId = Connection.instance.activeId;
    final sourceEndpoint = sourceId == null ? null : _endpoint(sourceId);
    final destination = destinations
        .where((d) => d.key == selected)
        .firstOrNull;
    if (sourceId == null || sourceEndpoint == null) {
      return _fail('Connect the source computer by Wi-Fi or USB.');
    }
    if (destination == null) {
      return _fail('Choose an available audio destination.');
    }
    phase = RemoteAudioPhase.connecting;
    message = 'Connecting audio…';
    notifyListeners();
    await _closeSockets();
    try {
      _AudioSocket? sink;
      String? destinationUrl;
      if (destination.phone) {
        await _native.invokeMethod('start', {
          'rate': 48000,
          'channels': 2,
          'latency': Settings.instance.remoteAudioLatency,
        });
      } else {
        final endpoint = _endpoint(destination.computerId);
        if (endpoint == null) {
          throw 'Destination computer is unavailable over Wi-Fi or USB.';
        }
        destinationUrl = endpoint.url;
        sink = await _AudioSocket.open(endpoint);
        await sink.command({'op': 'sink', 'device': destination.outputId});
        sink.socket.add(
          jsonEncode({'op': 'gain', 'volume': volume, 'muted': muted}),
        );
      }
      // Own each socket as soon as it opens so a later source/destination
      // setup error is cleaned up by the shared catch path.
      _sink = sink;
      _destinationUrl = destinationUrl;
      final source = await _AudioSocket.open(sourceEndpoint);
      _source = source;
      await source.command({
        'op': 'source',
        'playSource': Settings.instance.remoteAudioPlaySource,
      });
      _sourceId = sourceId;
      _sourceUrl = sourceEndpoint.url;
      _audioSub = source.binary.listen(
        (frame) {
          if (frame.length < 16 || frame[0] != 1 || frame[1] != 1) return;
          if (destination.phone) {
            _native
                .invokeMethod('write', Uint8List.sublistView(frame, 16))
                .ignore();
          } else {
            sink?.socket.add(frame);
          }
        },
        onError: (Object e) => _streamEnded('Audio stream failed: $e'),
        onDone: () => _streamEnded('The source audio connection ended.'),
      );
      source.closed.then(
        (_) => _streamEnded('The source audio connection ended.'),
      );
      sink?.closed.then(
        (_) => _streamEnded('The destination audio connection ended.'),
      );
      Settings.instance.update(
        () => Settings.instance.remoteAudioLastDestination = selected,
      );
      phase = RemoteAudioPhase.active;
      message = destination.label;
      notifyListeners();
    } catch (e) {
      await _closeSockets();
      await _native.invokeMethod('stop').catchError((_) {});
      _fail(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> stop() async {
    _reconnect?.cancel();
    _closing = true;
    await _closeSockets();
    await _native.invokeMethod('stop').catchError((_) {});
    _closing = false;
    phase = RemoteAudioPhase.idle;
    message = null;
    notifyListeners();
  }

  void setGain({double? level, bool? mute}) {
    if (level != null) volume = level.clamp(0, 1);
    if (mute != null) muted = mute;
    _sink?.socket.add(
      jsonEncode({'op': 'gain', 'volume': volume, 'muted': muted}),
    );
    _native.invokeMethod('gain', {'volume': volume, 'muted': muted}).ignore();
    notifyListeners();
  }

  Future<void> _closeSockets() async {
    await _audioSub?.cancel();
    _audioSub = null;
    final source = _source;
    final sink = _sink;
    _source = null;
    _sink = null;
    await Future.wait([
      if (source != null) source.close(),
      if (sink != null) sink.close(),
    ]);
  }

  void _streamEnded(String why) {
    if (_closing || !active) return;
    _fail(why);
    _closeSockets();
    _native.invokeMethod('stop').ignore();
  }

  void _connectionChanged() {
    if (!active || _closing || _sourceId == null) return;
    final source = _endpoint(_sourceId!);
    final destination = destinations
        .where((d) => d.key == selected)
        .firstOrNull;
    final dest = destination == null || destination.phone
        ? null
        : _endpoint(destination.computerId);
    if (source?.url == _sourceUrl && dest?.url == _destinationUrl) return;
    if (!Settings.instance.remoteAudioAutoReconnect) {
      _streamEnded(
        'The audio connection changed. Start it again on the new connection.',
      );
      return;
    }
    _closing = true;
    _closeSockets().whenComplete(() {
      _native.invokeMethod('stop').ignore();
      _closing = false;
      phase = RemoteAudioPhase.connecting;
      message = 'Audio connection changed — reconnecting…';
      notifyListeners();
      _reconnect?.cancel();
      _reconnect = Timer(const Duration(seconds: 1), () async {
        phase = RemoteAudioPhase.idle;
        await start();
      });
    });
  }

  void _fail(String text) {
    phase = RemoteAudioPhase.error;
    message = text;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    phase = RemoteAudioPhase.idle;
    message = null;
    destinations = const [];
    selected = 'phone';
    muted = false;
    volume = 1;
  }

  @visibleForTesting
  void debugShow({
    required RemoteAudioPhase state,
    List<RemoteAudioDestination> outputs = const [],
    String? note,
  }) {
    phase = state;
    destinations = outputs;
    message = note;
    if (!outputs.any((d) => d.key == selected)) {
      selected = outputs.firstOrNull?.key ?? 'phone';
    }
    notifyListeners();
  }
}
