import 'dart:async';
import 'dart:typed_data';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/remote_audio.dart';
import 'package:deskctrl/remote_audio_sheet.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    RemoteAudio.instance.debugReset();
  });

  test(
    'phone audio source setting persists and invalid values fall back',
    () async {
      Settings.instance.update(
        () => Settings.instance.remoteAudioSource = 'phone',
      );
      await Settings.instance.load();
      expect(Settings.instance.remoteAudioSource, 'phone');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remoteAudioSource', 'invalid');
      await Settings.instance.load();
      expect(Settings.instance.remoteAudioSource, 'computer');
    },
  );

  testWidgets('phone source panel fits landscape and explains capture limits', (
    tester,
  ) async {
    Settings.instance.remoteAudioSource = 'phone';
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RemoteAudioSheet())),
    );
    expect(find.byKey(const Key('remoteAudioSource')), findsOneWidget);
    expect(find.textContaining('Apps can block capture'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.byKey(const Key('remoteAudioStartStop'))).dy,
      lessThanOrEqualTo(360),
    );
  });

  testWidgets(
    'phone media reaches active computer output; reconnect, revoke and stop are safe',
    (tester) async {
      final agent = (await tester.runAsync(
        () => FakeAgent.start('speaker-token'),
      ))!;
      final audio = RemoteAudio.instance;
      final settings = Settings.instance;
      final messenger = tester.binding.defaultBinaryMessenger;
      const capture = MethodChannel('deskctrl/playback_capture');
      const events = EventChannel('deskctrl/playback_capture/audio');
      MockStreamHandlerEventSink? frames;
      final captureCalls = <MethodCall>[];
      final playbackCalls = <MethodCall>[];
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            frames = sink;
          },
          onCancel: (_) {
            frames = null;
          },
        ),
      );
      messenger.setMockMethodCallHandler(capture, (call) async {
        captureCalls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('deskctrl/remote_audio'),
        (call) async {
          playbackCalls.add(call);
          return null;
        },
      );
      addTearDown(() async {
        await audio.stop();
        await Connection.instance.disconnectAll();
        await agent.server.close(force: true);
        messenger.setMockStreamHandler(events, null);
        messenger.setMockMethodCallHandler(capture, null);
        messenger.setMockMethodCallHandler(
          const MethodChannel('deskctrl/remote_audio'),
          null,
        );
      });
      settings.saveDevice(
        Device(
          id: 'speaker',
          name: 'Speaker PC',
          host: '127.0.0.1',
          port: agent.port,
          token: 'speaker-token',
        ),
      );
      await tester.runAsync(() => Connection.instance.switchTo('speaker'));
      await tester.runAsync(() => audio.chooseSource('phone'));
      expect(audio.destinations.map((d) => d.key), ['speaker|default']);
      expect(audio.selected, 'speaker|default');
      await tester.runAsync(audio.start);
      expect(audio.active, isTrue, reason: audio.message);
      frames!.success(Uint8List.fromList(List.generate(3840, (i) => i % 256)));
      frames!.success(Uint8List(3840));
      frames!.success(Uint8List(4));
      await tester.pump();
      await tester.runAsync(settle);
      expect(agent.audioReceived.length, 2);
      final first = Uint8List.fromList(agent.audioReceived.first);
      final second = ByteData.sublistView(
        Uint8List.fromList(agent.audioReceived[1]),
      );
      expect(first.sublist(0, 4), [1, 1, 2, 1]);
      expect(ByteData.sublistView(first).getUint32(4, Endian.little), 48000);
      expect(second.getUint32(8, Endian.little), 1);
      expect(first.sublist(16), List.generate(3840, (i) => i % 256));
      expect(agent.audioCommands, isNot(contains('source')));
      expect(
        playbackCalls.where((c) => c.method == 'start' || c.method == 'write'),
        isEmpty,
      );
      audio.setGain(level: .3, mute: true);
      await tester.runAsync(settle);
      expect(
        agent.audioJson.lastWhere((c) => c['op'] == 'gain')['muted'],
        isTrue,
      );
      await tester.runAsync(() => audio.chooseSource('computer'));
      expect(
        settings.remoteAudioSource,
        'phone',
      ); // no source switch mid-stream

      settings.remoteAudioAutoReconnect = true;
      await tester.runAsync(() async {
        await agent.disconnectAudioOutput();
        await Future<void>.delayed(const Duration(milliseconds: 1450));
      });
      expect(audio.active, isTrue, reason: audio.message);
      expect(audio.selected, 'speaker|default');
      expect(captureCalls.where((c) => c.method == 'start').last.arguments, {
        'allowConsent': false,
      });
      frames!.success(Uint8List(3840));
      await tester.pump();
      await tester.runAsync(settle);
      expect(agent.audioReceived.length, 3);
      frames!.error(
        code: 'capture_stopped',
        message: 'Android revoked sharing',
      );
      await tester.pump();
      await tester.runAsync(settle);
      expect(audio.phase, RemoteAudioPhase.error);
      expect(audio.message, contains('Tap Start'));
      final attempts = captureCalls.where((c) => c.method == 'start').length;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)),
      );
      expect(captureCalls.where((c) => c.method == 'start').length, attempts);
      await tester.runAsync(audio.stop);
      expect(audio.phase, RemoteAudioPhase.idle);
      expect(captureCalls.last.method, 'stop');
      await tester.runAsync(() => audio.chooseSource('computer'));
      expect(audio.destinations.map((d) => d.key), ['phone']);
    },
  );

  testWidgets('denied phone capture cleans up the authenticated output', (
    tester,
  ) async {
    final agent = (await tester.runAsync(
      () => FakeAgent.start('denied-token'),
    ))!;
    final audio = RemoteAudio.instance;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      const EventChannel('deskctrl/playback_capture/audio'),
      MockStreamHandler.inline(onListen: (_, sink) {}),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('deskctrl/playback_capture'),
      (call) async {
        if (call.method == 'start') {
          throw PlatformException(
            code: 'playback_capture',
            message: 'Sharing was denied',
          );
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('deskctrl/remote_audio'),
      (_) async => null,
    );
    addTearDown(() async {
      await audio.stop();
      await Connection.instance.disconnectAll();
      await agent.server.close(force: true);
      messenger.setMockStreamHandler(
        const EventChannel('deskctrl/playback_capture/audio'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('deskctrl/playback_capture'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('deskctrl/remote_audio'),
        null,
      );
    });
    Settings.instance.saveDevice(
      Device(
        id: 'denied',
        name: 'Denied PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'denied-token',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('denied'));
    await tester.runAsync(() => audio.chooseSource('phone'));
    await tester.runAsync(audio.start);
    expect(audio.phase, RemoteAudioPhase.error);
    expect(audio.message, contains('Sharing was denied'));
    await tester.runAsync(settle);
    expect(agent.audioCommands, contains('stop'));
    expect(agent.audioCommands, isNot(contains('source')));
    // Stop while Android's consent prompt is pending must cancel setup and
    // leave neither a receiver socket nor a late capture session active.
    await tester.runAsync(() async {
      final consent = Completer<void>();
      messenger.setMockMethodCallHandler(
        const MethodChannel('deskctrl/playback_capture'),
        (call) async {
          if (call.method == 'start') {
            await consent.future;
          }
          if (call.method == 'stop' && !consent.isCompleted) {
            consent.completeError(
              PlatformException(code: 'cancelled', message: 'Cancelled'),
            );
          }
          return null;
        },
      );
      final starting = audio.start();
      await settle();
      expect(audio.phase, RemoteAudioPhase.connecting);
      await audio.stop();
      await starting;
    });
    expect(audio.phase, RemoteAudioPhase.idle);
  });
}
