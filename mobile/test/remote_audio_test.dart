import 'package:deskctrl/remote_audio.dart';
import 'package:deskctrl/remote_audio_sheet.dart';
import 'package:deskctrl/connection.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    RemoteAudio.instance.debugReset();
  });

  test('remote audio preferences are saved and restored', () async {
    final s = Settings.instance;
    s.update(() {
      s.remoteAudioEnabled = false;
      s.remoteAudioAutoReconnect = true;
      s.remoteAudioPlaySource = true;
      s.remoteAudioLatency = 'low';
      s.remoteAudioLastDestination = 'pc|headphones';
    });
    await s.load();
    expect(s.remoteAudioEnabled, isFalse);
    expect(s.remoteAudioAutoReconnect, isTrue);
    expect(s.remoteAudioPlaySource, isTrue);
    expect(s.remoteAudioLatency, 'low');
    expect(s.remoteAudioLastDestination, 'pc|headphones');
  });

  testWidgets('audio panel lists destinations and selects one', (tester) async {
    RemoteAudio.instance.debugShow(
      state: RemoteAudioPhase.idle,
      outputs: const [
        RemoteAudioDestination(
          key: 'phone',
          computerId: '',
          computerName: '',
          outputId: 'android',
          outputName: 'Android media output',
          phone: true,
        ),
        RemoteAudioDestination(
          key: 'pc|headphones',
          computerId: 'pc',
          computerName: 'Studio PC',
          outputId: 'headphones',
          outputName: 'USB headphones',
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RemoteAudioSheet())),
    );
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('Studio PC — USB headphones'), findsOneWidget);
    await tester.tap(find.byKey(const Key('audioDestination-pc|headphones')));
    await tester.pump();
    expect(RemoteAudio.instance.selected, 'pc|headphones');
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('active stream exposes mute, volume and Stop', (tester) async {
    RemoteAudio.instance.debugShow(
      state: RemoteAudioPhase.active,
      note: 'This phone',
      outputs: const [
        RemoteAudioDestination(
          key: 'phone',
          computerId: '',
          computerName: '',
          outputId: 'android',
          outputName: 'Android media output',
          phone: true,
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RemoteAudioSheet())),
    );
    expect(find.byKey(const Key('remoteAudioMute')), findsOneWidget);
    expect(find.byKey(const Key('remoteAudioVolume')), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remoteAudioMute')));
    await tester.pump();
    expect(RemoteAudio.instance.muted, isTrue);
  });

  testWidgets(
    'audio streams to the phone and relays unchanged to another computer',
    (tester) async {
      final source = (await tester.runAsync(
        () => FakeAgent.start('source-token'),
      ))!;
      final destination = (await tester.runAsync(
        () => FakeAgent.start('destination-token'),
      ))!;
      addTearDown(() async {
        await RemoteAudio.instance.stop();
        await Connection.instance.disconnectAll();
        await source.server.close(force: true);
        await destination.server.close(force: true);
      });
      final s = Settings.instance;
      s.saveDevice(
        Device(
          id: 'source',
          name: 'Source',
          host: 'localhost',
          port: source.port,
          token: 'source-token',
        ),
      );
      s.saveDevice(
        Device(
          id: 'destination',
          name: 'Destination',
          host: '127.0.0.1',
          port: destination.port,
          token: 'destination-token',
        ),
      );
      await tester.runAsync(() => Connection.instance.switchTo('source'));
      await tester.runAsync(
        () => Connection.instance.connectDevice('destination'),
      );

      final nativeCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('deskctrl/remote_audio'),
        (call) async {
          nativeCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('deskctrl/remote_audio'),
          null,
        ),
      );

      await tester.runAsync(RemoteAudio.instance.discover);
      expect(
        RemoteAudio.instance.destinations.map((d) => d.key),
        contains('destination|default'),
      );

      RemoteAudio.instance.select('phone');
      await tester.runAsync(RemoteAudio.instance.start);
      source.sendAudio([1, 2, 3, 4]);
      await tester.runAsync(settle);
      final write = nativeCalls.where((c) => c.method == 'write').last;
      expect((write.arguments as Uint8List).toList(), [1, 2, 3, 4]);

      // A transport change stops safely with a clear state when auto-reconnect is off.
      final sourceSession = Connection.instance.active!;
      sourceSession.usb
        ..port = source.port
        ..token = 'source-token'
        ..setState(LinkState.connected);
      await tester.runAsync(settle);
      expect(
        RemoteAudio.instance.phase,
        RemoteAudioPhase.error,
        reason: RemoteAudio.instance.message,
      );
      expect(RemoteAudio.instance.message, contains('connection changed'));
      await tester.runAsync(RemoteAudio.instance.stop);
      sourceSession.usb.setState(LinkState.disconnected);

      RemoteAudio.instance.select('destination|default');
      await tester.runAsync(RemoteAudio.instance.start);
      source.sendAudio([5, 6, 7, 8]);
      await tester.runAsync(settle);
      expect(destination.audioReceived.last.sublist(16), [5, 6, 7, 8]);
      RemoteAudio.instance.setGain(level: .4, mute: true);
      await tester.runAsync(settle);
      final gain = destination.audioJson.lastWhere((c) => c['op'] == 'gain');
      expect(gain['volume'], closeTo(.4, .001));
      expect(gain['muted'], isTrue);
      await tester.runAsync(destination.disconnectAudioOutput);
      await tester.runAsync(settle);
      expect(RemoteAudio.instance.phase, RemoteAudioPhase.error);
      expect(RemoteAudio.instance.message, contains('destination'));
      expect(
        source.audioCommands,
        containsAllInOrder(['source', 'stop', 'source']),
      );
      expect(destination.audioCommands, containsAll(['discover', 'sink']));
    },
  );

  testWidgets('audio reconnects after its transport changes when enabled', (
    tester,
  ) async {
    final source = (await tester.runAsync(
      () => FakeAgent.start('source-token'),
    ))!;
    addTearDown(() async {
      await RemoteAudio.instance.stop();
      await Connection.instance.disconnectAll();
      await source.server.close(force: true);
    });
    Settings.instance
      ..remoteAudioAutoReconnect = true
      ..saveDevice(
        Device(
          id: 'source',
          name: 'Source',
          host: 'localhost',
          port: source.port,
          token: 'source-token',
        ),
      );
    await tester.runAsync(() => Connection.instance.switchTo('source'));

    final nativeCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('deskctrl/remote_audio'),
      (call) async {
        nativeCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('deskctrl/remote_audio'),
        null,
      ),
    );

    await tester.runAsync(RemoteAudio.instance.discover);
    await tester.runAsync(RemoteAudio.instance.start);
    expect(RemoteAudio.instance.phase, RemoteAudioPhase.active);

    await tester.runAsync(() async {
      // Create the reconnect Timer in the real-time zone because it starts
      // real WebSocket I/O when it fires.
      final sourceSession = Connection.instance.active!;
      sourceSession.usb
        ..port = source.port
        ..token = 'source-token'
        ..setState(LinkState.connected);
      await settle();
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      while (RemoteAudio.instance.phase != RemoteAudioPhase.active &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });

    expect(
      RemoteAudio.instance.phase,
      RemoteAudioPhase.active,
      reason:
          '${RemoteAudio.instance.message}; native=${nativeCalls.map((c) => c.method).toList()}; connections=${source.audioConnections}; commands=${source.audioCommands}',
    );
    expect(
      source.audioCommands.where((op) => op == 'source').length,
      greaterThanOrEqualTo(2),
    );
    expect(nativeCalls.where((c) => c.method == 'start').length, 2);
  });
}
