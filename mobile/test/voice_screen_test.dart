import 'dart:typed_data';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/modes.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/voice.dart';
import 'package:deskctrl/voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

class _Mic implements MicSource {
  void Function(Uint8List)? cb;
  bool running = false;
  @override
  Future<bool> start(void Function(Uint8List) onData) async {
    cb = onData;
    running = true;
    return true;
  }

  @override
  Future<void> stop() async => running = false;
}

void main() {
  late FakeAgent agent;
  late _Mic mic;

  Future<void> setUpApp(WidgetTester tester, {Widget? home}) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
    Settings.instance.saveDevice(
      Device(
        id: 'vs',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('vs'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    mic = _Mic();
    VoiceController.instance.mic = mic;
    VoiceController.instance.reset();
    addTearDown(() async {
      await Connection.instance.disconnectAll();
      await agent.server.close(force: true);
    });
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: home ?? const VoiceScreen())),
    );
    await tester.pump();
  }

  Future<void> real(WidgetTester tester, [int ms = 500]) async {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: ms)),
    );
    await tester.pump();
  }

  void speak() {
    final b = ByteData(640);
    for (var i = 0; i < 320; i++) {
      b.setInt16(i * 2, i.isEven ? 5000 : -5000, Endian.little);
    }
    mic.cb?.call(b.buffer.asUint8List());
  }

  testWidgets('hold Dictate, speak, let go: the words are typed and shown', (
    tester,
  ) async {
    await setUpApp(tester);
    agent.voiceText = 'hi';
    expect(find.text('Hold a button and speak'), findsOneWidget);
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('voiceDictate'))),
    );
    await real(tester, 50);
    expect(find.text('Listening...'), findsOneWidget);
    speak();
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(find.text('Recognising...'), findsOneWidget);
    await real(tester, 800);
    expect(
      agent.received.where((m) => m.startsWith('1,')).length,
      3,
      reason: 'h, i, space',
    );
    expect(
      find.text('hi'),
      findsOneWidget,
      reason: 'in the list of what was said',
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Command with a risky phrase shows the question; Run does it', (
    tester,
  ) async {
    await setUpApp(tester);
    agent.voiceText = 'close this window';
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('voiceCommand'))),
    );
    await real(tester, 50);
    speak();
    await g.up();
    await real(tester, 800);
    expect(find.byKey(const Key('voiceRun')), findsOneWidget);
    expect(find.text('Run "Close application"'), findsOneWidget);
    expect(agent.received.where((m) => m.startsWith('1,')), isEmpty);
    await tester.tap(find.byKey(const Key('voiceRun')));
    await real(tester, 400);
    expect(
      agent.received.where((m) => m.startsWith('1,')),
      contains('1,0,61'),
      reason: 'F4',
    );
    expect(find.byKey(const Key('voiceRun')), findsNothing);
  });

  testWidgets('tap mode: tap to start, tap again to stop', (tester) async {
    await setUpApp(tester);
    Settings.instance.update(() => Settings.instance.voiceHold = false);
    await tester.pump();
    agent.voiceText = 'hi';
    expect(find.text('Tap a button, speak, tap again'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voiceDictate')));
    await real(tester, 50);
    expect(
      find.text('Listening...'),
      findsOneWidget,
      reason: 'it keeps listening after the tap',
    );
    speak();
    await tester.tap(find.byKey(const Key('voiceDictate')));
    await real(tester, 800);
    expect(mic.running, isFalse);
    expect(find.text('hi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the engine is missing on the computer: the screen says so', (
    tester,
  ) async {
    await setUpApp(tester);
    agent.voiceText = null;
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('voiceDictate'))),
    );
    await real(tester, 600);
    await g.up();
    await real(tester, 100);
    expect(find.text('not installed'), findsOneWidget);
  });

  testWidgets('Voice is a screen of its own next to keyboard and mousepad', (
    tester,
  ) async {
    await setUpApp(tester, home: const Home());
    expect(Mode.voice.label, 'Voice');
    // The mode button cycles keyboard -> mouse -> trackpad -> voice.
    final modes = availableModes(
      mouse: Settings.instance.mouseTab,
      pad: Settings.instance.padTab,
      voice: Settings.instance.voiceTab,
      order: Settings.instance.modeOrderList,
    );
    expect(modes, [Mode.keyboard, Mode.mouse, Mode.pad, Mode.voice]);
    Settings.instance.update(() => Settings.instance.voiceTab = false);
    expect(
      availableModes(
        mouse: true,
        pad: true,
        voice: Settings.instance.voiceTab,
        order: Settings.instance.modeOrderList,
      ),
      isNot(contains(Mode.voice)),
    );
  });
}
