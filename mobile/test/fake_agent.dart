import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for a desktop agent: checks the token, answers "ok", records input,
/// and sends a heartbeat every second like the real one.
class FakeAgent {
  late final HttpServer server;
  final List<String> received = [];
  final List<String> audioCommands = [];
  final List<Map<String, dynamic>> audioJson = [];
  final List<List<int>> audioReceived = [];
  final List<Map<String, String>> audioOutputs = [
    {'id': 'default', 'label': 'System default'},
  ];
  WebSocket? audioSource;
  WebSocket? audioSink;
  int audioConnections = 0;
  int connections = 0;

  /// Lock lights reported after the token is accepted; null = this computer reports none.
  int? leds;
  WebSocket? socket;

  /// Every connection so far, oldest first.
  final List<WebSocket> sockets = [];

  /// Sent right after the token is accepted, like the real agent does on the USB cable:
  /// `id=..&ip=..&port=..&bt=..&name=..`.
  String? info;

  /// Tell the app a text field got the keyboard focus on the computer.
  void textFocus({bool typeable = true, bool old = false}) =>
      socket?.add(old ? <int>[0x13] : <int>[0x13, typeable ? 1 : 0]);

  /// Send a volume / brightness report (255 = unknown) like the real agent does.
  void report(int volume, int brightness, {bool muted = false}) =>
      socket?.add(<int>[0x12, volume, brightness, muted ? 1 : 0]);

  /// Simulates a dead link (Wi-Fi switched off): no heartbeats, and everything received is ignored.
  bool silent = false;

  /// Connections that went silent (a cable pulled out: nothing arrives and nothing is closed).
  final Set<WebSocket> muted = {};

  /// Voice (see agent/src/voice.rs): what the agent answers to a finished recording / an intent
  /// request, and how many audio bytes it was sent. Null text = the engine is not installed.
  String? voiceText;
  String voiceIntent = '{"t":"intent","calls":[],"confidence":0.1}';
  int voiceAudioBytes = 0;

  /// Takes the recording but never answers (a computer that is far too slow).
  bool voiceMute = false;
  final List<int> voiceModes = [];

  /// Splits a JSON answer into the 0x15 frames the real agent sends.
  void sayVoice(String json, [WebSocket? to]) {
    final bytes = utf8.encode(json);
    final n = (bytes.length / 248).ceil().clamp(1, 1 << 20);
    for (var i = 0; i < n; i++) {
      final piece = bytes.sublist(
        i * 248,
        ((i + 1) * 248).clamp(0, bytes.length),
      );
      (to ?? socket)?.add(<int>[0x15, i + 1 == n ? 1 : 0, ...piece]);
    }
  }

  /// An older agent sends no heartbeats.
  bool heartbeats = true;

  static Future<FakeAgent> start(
    String token, {
    int? leds,
    bool heartbeats = true,
    int port = 0,
  }) async {
    final a = FakeAgent()
      ..leds = leds
      ..heartbeats = heartbeats;
    a.server = await HttpServer.bind('127.0.0.1', port);
    a.server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      if (req.uri.path == '/audio/v1') {
        a.audioConnections++;
        a._serveAudio(ws, token);
        return;
      }
      a.connections++;
      a.socket = ws;
      a.sockets.add(ws);
      var authed = false;
      Timer? beat;
      ws.done.whenComplete(() => beat?.cancel());
      ws.listen((m) {
        if (a.silent || a.muted.contains(ws)) return;
        if (!authed) {
          if (m == token) {
            authed = true;
            ws.add('ok');
            if (a.info != null) ws.add(<int>[0x14, ...a.info!.codeUnits]);
            if (a.leds != null) ws.add(<int>[0x10, a.leds!]);
            if (a.heartbeats) {
              ws.add(<int>[0x11]); // right away, like the real agent
            }
            beat = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!a.silent && !a.muted.contains(ws) && a.heartbeats) {
                ws.add(<int>[0x11]);
              }
            });
          } else {
            ws.close();
          }
        } else if (m is List<int>) {
          if (m.length == 1 && m[0] == 0x00) return; // the app's keep-alive
          if (m.length >= 2 && m[0] == 0x06) {
            switch (m[1]) {
              case 1:
                a.voiceModes.add(m.length > 2 ? m[2] : 0);
                if (a.voiceText == null)
                  a.sayVoice('{"t":"unavailable","msg":"not installed"}', ws);
              case 2:
                a.voiceAudioBytes += m.length - 2;
              case 3:
                if (a.voiceText != null && !a.voiceMute) {
                  a.sayVoice(
                    jsonEncode({'t': 'text', 'text': a.voiceText}),
                    ws,
                  );
                }
              case 5:
                a.received.add('intent:${utf8.decode(m.sublist(2))}');
                a.sayVoice(a.voiceIntent, ws);
            }
            return;
          }
          a.received.add(m.join(','));
        }
      });
    });
    return a;
  }

  void _serveAudio(WebSocket ws, String token) {
    var authed = false;
    ws.listen((m) {
      if (!authed) {
        if (m == token) {
          authed = true;
          ws.add('ok');
        } else {
          ws.close();
        }
        return;
      }
      if (m is String) {
        final command = jsonDecode(m) as Map<String, dynamic>;
        final op = command['op'] as String? ?? '';
        audioCommands.add(op);
        audioJson.add(command);
        switch (op) {
          case 'discover':
            ws.add(
              jsonEncode({
                'op': 'devices',
                'version': 1,
                'computerId': 'fake-$port',
                'name': 'Fake $port',
                'capture': true,
                'outputs': audioOutputs,
              }),
            );
            return;
          case 'source':
            audioSource = ws;
            ws.add(jsonEncode({'op': 'active', 'role': 'source'}));
            return;
          case 'sink':
            audioSink = ws;
            ws.add(jsonEncode({'op': 'active', 'role': 'sink'}));
            return;
          case 'gain':
            return;
          case 'stop':
            ws.close();
            return;
        }
      } else if (m is List<int>) {
        audioReceived.add(List<int>.from(m));
      }
    });
  }

  void sendAudio(List<int> pcm) {
    if (audioSource?.readyState != WebSocket.open) return;
    final header = <int>[1, 1, 2, 1, 0x80, 0xBB, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0];
    try {
      audioSource?.add([...header, ...pcm]);
    } on StateError {
      // A capture frame can race the peer's close handshake.
    }
  }

  Future<void> disconnectAudioOutput() async => audioSink?.close();

  int get port => server.port;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 200));

/// Stands in for the Kotlin Bluetooth bridge (MainActivity.kt): accepts a connection,
/// acknowledges the token, records what the app writes, and sends heartbeats.
class FakeBt {
  FakeBt(this.token);

  final String token;
  final List<String> written = []; // payloads the app sent (no keep-alives)
  bool connected = false;

  /// Computers this phone is paired with: (name, address).
  final List<(String, String)> bonded = [];

  /// Simulates a dead link: nothing is acknowledged or sent.
  bool silent = false;
  Timer? _beat;
  String? _address;

  static const _events = 'deskctrl/bt/events';

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('deskctrl/bt'), (
      call,
    ) async {
      switch (call.method) {
        case 'ensurePermission':
          return true;
        case 'bondedDevices':
          return [
            for (final b in bonded) {'name': b.$1, 'address': b.$2},
          ];
        case 'connect':
          _address = (call.arguments as Map)['address'] as String;
          connected = true;
          return null;
        case 'write':
          if (silent) return null;
          final bytes = ((call.arguments as Map)['bytes'] as Uint8List)
              .toList();
          _onWrite(bytes);
          return null;
        case 'disconnect':
          connected = false;
          _beat?.cancel();
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel(_events),
      (call) async => null,
    );
  }

  void uninstall() {
    _beat?.cancel();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('deskctrl/bt'),
      null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel(_events), null);
  }

  void _onWrite(List<int> framed) {
    final payload = framed.sublist(1);
    if (String.fromCharCodes(payload) == token) {
      _emit({
        't': 'data',
        'id': _address,
        'b': Uint8List.fromList([1, 0x06]),
      }); // ACK
      _emit({
        't': 'data',
        'id': _address,
        'b': Uint8List.fromList([1, 0x11]),
      }); // first heartbeat, right away
      _beat = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!silent && connected) {
          _emit({
            't': 'data',
            'id': _address,
            'b': Uint8List.fromList([1, 0x11]),
          });
        }
      });
    } else if (payload.length == 1 && payload[0] == 0x00) {
      // keep-alive
    } else {
      written.add(payload.join(','));
    }
  }

  void _emit(Map<String, Object?> event) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _events,
          const StandardMethodCodec().encodeSuccessEnvelope(event),
          (_) {},
        );
  }
}
