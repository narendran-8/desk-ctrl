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
    ws.pingInterval = const Duration(seconds: 15);
    ws.add(endpoint.token);
    try {
      await accepted.future.timeout(const Duration(seconds: 4));
    } catch (_) {
      await ws.close();
      rethrow;
    }
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
  static const _capture = MethodChannel('deskctrl/playback_capture');
  static const _captureEvents = EventChannel('deskctrl/playback_capture/audio');
  bool get phoneSource => Settings.instance.remoteAudioSource == 'phone';
  String get sourceLabel => phoneSource
      ? 'This phone'
      : Settings.instance
                .deviceById(
                  (active || phase == RemoteAudioPhase.connecting
                          ? _sourceId
                          : Connection.instance.activeId) ??
                      '',
                )
                ?.title ??
            'No source computer';

  Future<void> chooseSource(String value) async {
    if (active ||
        phase == RemoteAudioPhase.connecting ||
        phase == RemoteAudioPhase.discovering) {
      return;
    }
    Settings.instance.update(
      () => Settings.instance.remoteAudioSource = value == 'phone'
          ? 'phone'
          : 'computer',
    );
    await discover();
  }

  Future<void> setPlayPhone(bool enabled) async {
    if (phase == RemoteAudioPhase.connecting) return;
    if (phoneSource && active) {
      try {
        await _capture.invokeMethod('playPhone', {'enabled': enabled});
      } catch (e) {
        await stop();
        _fail('Could not change phone playback: $e');
        return;
      }
    }
    Settings.instance.update(
      () => Settings.instance.remoteAudioPlayPhone = enabled,
    );
    notifyListeners();
  }

  Future<void> _stopCapture() async {
    if (phoneSource) await _capture.invokeMethod('stop').catchError((_) {});
  }

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
  StreamSubscription<dynamic>? _audioSub;
  bool _closing = false;
  Timer? _reconnect;
  Future<void>? _recoveryCleanup;
  bool _wanted = false;
  int _generation = 0, _retryCount = 0;
  int _captureSequence = 0;
  final _statusSubs = <StreamSubscription<String>>[];

  bool get active => phase == RemoteAudioPhase.active;
  void preferencesChanged() => notifyListeners();

  void select(String key) {
    if (active ||
        phase == RemoteAudioPhase.connecting ||
        !destinations.any((d) => d.key == key)) {
      return;
    }
    selected = key;
    notifyListeners();
  }

  _Endpoint? _endpoint(String deviceId, {String? preferred}) {
    final session = Connection.instance.connectedSession(deviceId);
    if (session == null) return null;
    final d = session.device;
    if (preferred != null &&
        session.wifi.connected &&
        d.host.isNotEmpty &&
        preferred == 'ws://${d.host}:${d.port}/audio/v1') {
      return _Endpoint(preferred, d.token);
    }
    if (session.usb.connected) {
      return _Endpoint('ws://127.0.0.1:${d.port}/audio/v1', d.token);
    }
    if (session.wifi.connected && d.host.isNotEmpty) {
      return _Endpoint('ws://${d.host}:${d.port}/audio/v1', d.token);
    }
    return null; // the control RFCOMM frame is deliberately too small for audio
  }

  Future<void> discover() async {
    if (!Settings.instance.remoteAudioEnabled ||
        active ||
        phase == RemoteAudioPhase.connecting) {
      return;
    }
    phase = RemoteAudioPhase.discovering;
    message = null;
    notifyListeners();
    final sourceId = Connection.instance.activeId;
    final found = <RemoteAudioDestination>[
      if (!phoneSource)
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
      if (!phoneSource && id == sourceId) continue;
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
    selected = found.any((d) => d.key == remembered)
        ? remembered
        : found.firstOrNull?.key ?? '';
    phase = RemoteAudioPhase.idle;
    notifyListeners();
  }

  Future<void> start({bool retry = false}) async {
    await _recoveryCleanup;
    if (phase == RemoteAudioPhase.connecting || active) return;
    if (!Settings.instance.remoteAudioEnabled) return;
    if (!retry) {
      _retryCount = 0;
      _wanted = true;
    }
    _reconnect?.cancel();
    final sourceId = retry ? _sourceId : Connection.instance.activeId;
    final sourceEndpoint = sourceId == null
        ? null
        : _endpoint(sourceId, preferred: retry ? _sourceUrl : null);
    final destination = destinations
        .where((d) => d.key == selected)
        .firstOrNull;
    if (!phoneSource && (sourceId == null || sourceEndpoint == null)) {
      return _startFailed(
        'Connect the source computer by Wi-Fi or USB.',
        retry,
      );
    }
    if (destination == null || (phoneSource && destination.phone)) {
      return _startFailed('Choose an available audio destination.', retry);
    }
    _sourceId = sourceId;
    phase = RemoteAudioPhase.connecting;
    message = retry ? 'Reconnecting audio…' : 'Connecting audio…';
    notifyListeners();
    await _closeSockets();
    final generation = _generation;
    bool current() => _wanted && generation == _generation;
    try {
      if (!current()) return;
      _AudioSocket? sink;
      String? destinationUrl;
      if (destination.phone) {
        await _native.invokeMethod('start', {
          'rate': 48000,
          'channels': 2,
          'latency': Settings.instance.remoteAudioLatency,
        });
      } else {
        final endpoint = _endpoint(
          destination.computerId,
          preferred: retry ? _destinationUrl : null,
        );
        if (endpoint == null) {
          throw 'Destination computer is unavailable over Wi-Fi or USB.';
        }
        destinationUrl = endpoint.url;
        sink = await _AudioSocket.open(endpoint);
        if (!current()) {
          await sink.close();
          return;
        }
        _sink = sink;
        await sink.command({'op': 'sink', 'device': destination.outputId});
        sink.socket.add(
          jsonEncode({'op': 'gain', 'volume': volume, 'muted': muted}),
        );
      }
      // Own each socket as soon as it opens so a later source/destination
      // setup error is cleaned up by the shared catch path.
      if (!current()) return;
      _sink = sink;
      _destinationUrl = destinationUrl;
      if (phoneSource) {
        _captureSequence = 0;
        _audioSub = _captureEvents.receiveBroadcastStream().listen(
          (dynamic data) {
            if (!current() || data is! Uint8List || data.length != 3840) return;
            final frame = Uint8List(16 + data.length);
            frame.setAll(0, [1, 1, 2, 1]);
            final header = ByteData.sublistView(frame);
            header.setUint32(4, 48000, Endian.little);
            header.setUint32(8, _captureSequence++ & 0xffffffff, Endian.little);
            header.setUint32(
              12,
              DateTime.now().millisecondsSinceEpoch & 0xffffffff,
              Endian.little,
            );
            frame.setAll(16, data);
            try {
              sink?.socket.add(frame);
            } catch (e) {
              _streamEnded('Destination audio send failed: $e', generation);
            }
          },
          onError: (Object e) {
            // Revoked consent must never reopen an Android dialog automatically.
            if (!currentGeneration(generation) || !_wanted) return;
            _wanted = false;
            if (currentGeneration(generation)) {
              stop().then((_) {
                if (!_wanted && phase == RemoteAudioPhase.idle) {
                  _fail(
                    'Phone audio capture stopped: $e. Tap Start to allow capture again.',
                  );
                }
              });
            }
          },
        );
        await _capture.invokeMethod('start', {
          'allowConsent': !retry,
          'playPhone': Settings.instance.remoteAudioPlayPhone,
        });
        if (!current()) {
          await _stopCapture();
          return;
        }
      }
      final source = phoneSource
          ? null
          : await _AudioSocket.open(sourceEndpoint!);
      if (!current()) {
        await source?.close();
        return;
      }
      _source = source;
      await source?.command({
        'op': 'source',
        'playSource': Settings.instance.remoteAudioPlaySource,
      });
      if (!current()) return;
      _sourceUrl = phoneSource ? null : sourceEndpoint!.url;
      if (source != null) {
        _audioSub = source.binary.listen(
          (frame) {
            if (frame.length < 16 || frame[0] != 1 || frame[1] != 1) return;
            if (destination.phone) {
              _native
                  .invokeMethod('write', Uint8List.sublistView(frame, 16))
                  .catchError((Object e) {
                    _streamEnded('Phone audio output failed: $e', generation);
                    return null;
                  });
            } else {
              try {
                sink?.socket.add(frame);
              } catch (e) {
                _streamEnded('Destination audio send failed: $e', generation);
              }
            }
          },
          onError: (Object e) =>
              _streamEnded('Audio stream failed: $e', generation),
          onDone: () =>
              _streamEnded('The source audio connection ended.', generation),
        );
      }
      source?.closed.then(
        (_) => _streamEnded('The source audio connection ended.', generation),
      );
      sink?.closed.then(
        (_) =>
            _streamEnded('The destination audio connection ended.', generation),
      );
      for (final socket in [?source, ?sink]) {
        _statusSubs.add(
          socket.text.listen(
            (text) {
              final status = jsonDecode(text) as Map<String, dynamic>;
              if (status['op'] == 'error') {
                _streamEnded(
                  status['message']?.toString() ?? 'Audio output unavailable',
                  generation,
                );
              }
            },
            onError: (Object e) =>
                _streamEnded('Audio connection failed: $e', generation),
          ),
        );
      }
      Settings.instance.update(
        () => Settings.instance.remoteAudioLastDestination = selected,
      );
      phase = RemoteAudioPhase.active;
      message = destination.label;
      notifyListeners();
    } catch (e) {
      if (!current()) return;
      await _closeSockets();
      await _native.invokeMethod('stop').catchError((_) {});
      if (e is PlatformException && e.code == 'capture_consent_required') {
        retry = false;
      }
      if (!retry || !Settings.instance.remoteAudioAutoReconnect) {
        await _stopCapture();
      }
      if (_wanted) {
        _startFailed(e.toString().replaceFirst('Exception: ', ''), retry);
      }
    }
  }

  void _startFailed(String why, bool retry) {
    if (retry && _wanted && Settings.instance.remoteAudioAutoReconnect) {
      _scheduleRetry(why);
    } else {
      _wanted = false;
      _stopCapture();
      _fail(why);
    }
  }

  Future<void> stop() async {
    _wanted = false;
    _reconnect?.cancel();
    await _recoveryCleanup;
    _closing = true;
    await _closeSockets();
    await _native.invokeMethod('stop').catchError((_) {});
    await _stopCapture();
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
    _generation++;
    for (final sub in _statusSubs) {
      await sub.cancel();
    }
    _statusSubs.clear();
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

  void _streamEnded(String why, [int? generation]) {
    if ((generation != null && generation != _generation) ||
        _closing ||
        !active) {
      return;
    }
    _recover(why);
  }

  Future<void> _recover(String why) async {
    _closing = true;
    phase = Settings.instance.remoteAudioAutoReconnect
        ? RemoteAudioPhase.connecting
        : RemoteAudioPhase.error;
    message = why;
    notifyListeners();
    final cleanup = () async {
      await _closeSockets();
      await _native.invokeMethod('stop').catchError((_) {});
    }();
    _recoveryCleanup = cleanup;
    await cleanup;
    _recoveryCleanup = null;
    _closing = false;
    if (!_wanted) return;
    if (Settings.instance.remoteAudioEnabled &&
        Settings.instance.remoteAudioAutoReconnect) {
      _scheduleRetry(why);
    } else {
      _wanted = false;
      _stopCapture();
      _fail(why);
    }
  }

  void _scheduleRetry(String why) {
    _reconnect?.cancel();
    final seconds = 1 << _retryCount.clamp(0, 3);
    _retryCount++;
    phase = RemoteAudioPhase.connecting;
    message = '$why Reconnecting to the same output in $seconds s…';
    notifyListeners();
    _reconnect = Timer(Duration(seconds: seconds), () {
      if (!_wanted ||
          !Settings.instance.remoteAudioEnabled ||
          !Settings.instance.remoteAudioAutoReconnect) {
        if (_wanted) {
          _wanted = false;
          _stopCapture();
          _fail('Automatic audio reconnection is disabled.');
        }
        return;
      }
      phase = RemoteAudioPhase.idle;
      start(retry: true);
    });
  }

  void _connectionChanged() {
    if (!active || _closing || (!phoneSource && _sourceId == null)) return;
    final source = phoneSource
        ? null
        : _endpoint(_sourceId!, preferred: _sourceUrl);
    final destination = destinations
        .where((d) => d.key == selected)
        .firstOrNull;
    final dest = destination == null || destination.phone
        ? null
        : _endpoint(destination.computerId, preferred: _destinationUrl);
    if (source?.url == _sourceUrl && dest?.url == _destinationUrl) return;
    _streamEnded('The audio connection changed.');
  }

  bool currentGeneration(int generation) => generation == _generation;

  void _fail(String text) {
    phase = RemoteAudioPhase.error;
    message = text;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _wanted = false;
    _reconnect?.cancel();
    _retryCount = 0;
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
