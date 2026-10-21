import 'package:deskctrl/connection.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  late FakeAgent agent;

  Future<void> setUpPad(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
    Settings.instance.saveDevice(
      Device(
        id: 'nav',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('nav'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PadScreen())),
    );
    await tester.pump();
    addTearDown(() async {
      await Connection.instance.disconnectAll();
      await agent.server.close(force: true);
    });
  }

  /// Two fingers side by side move by [dx], [dy] in steps, then lift.
  Future<void> twoFingers(
    WidgetTester tester,
    double dx,
    double dy, {
    int steps = 10,
  }) async {
    final c = tester.getCenter(find.byType(TouchPad));
    final a = await tester.startGesture(c + const Offset(-30, 0));
    final b = await tester.startGesture(c + const Offset(30, 0));
    for (var i = 0; i < steps; i++) {
      await a.moveBy(Offset(dx / steps, dy / steps));
      await b.moveBy(Offset(dx / steps, dy / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(
      const Duration(seconds: 2),
    ); // the on-screen message fades
  }

  const back = ['1,0,226', '1,0,80', '2,0,80', '2,0,226']; // Alt+Left
  const forward = ['1,0,226', '1,0,79', '2,0,79', '2,0,226']; // Alt+Right
  List<String> frames(String prefix) => [
    for (final m in agent.received)
      if (m.startsWith(prefix)) m,
  ];

  testWidgets(
    'two fingers from right to left = Back, from left to right = Forward',
    (tester) async {
      await setUpPad(tester);
      await twoFingers(tester, -200, 0);
      expect(agent.received, back);
      agent.received.clear();
      await twoFingers(tester, 200, 0);
      expect(agent.received, forward);
    },
  );

  testWidgets('a swipe is not also a sideways scroll, and not a click', (
    tester,
  ) async {
    await setUpPad(tester);
    await twoFingers(tester, -200, 0);
    expect(frames('5,'), isEmpty, reason: 'no scroll frames');
    expect(frames('4,'), isEmpty, reason: 'no right click');
  });

  testWidgets(
    'too short, or mostly up and down: no Back / Forward; up and down still scrolls',
    (tester) async {
      await setUpPad(tester);
      await twoFingers(tester, -50, 0);
      expect(
        agent.received.where((m) => m.startsWith('1,')),
        isEmpty,
        reason: 'too short',
      );
      agent.received.clear();
      await twoFingers(tester, -100, 160);
      expect(
        agent.received.where((m) => m.startsWith('1,')),
        isEmpty,
        reason: 'mostly vertical',
      );
      expect(frames('5,'), isNotEmpty, reason: 'it scrolled');
      agent.received.clear();
      await twoFingers(tester, 0, 200);
      expect(frames('5,'), isNotEmpty);
      expect(agent.received.where((m) => m.startsWith('1,')), isEmpty);
    },
  );

  testWidgets('pinching is not a swipe', (tester) async {
    await setUpPad(tester);
    final c = tester.getCenter(find.byType(TouchPad));
    final a = await tester.startGesture(c + const Offset(-30, 0));
    final b = await tester.startGesture(c + const Offset(30, 0));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-12, 0));
      await b.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      agent.received.where(
        (m) => m == '1,0,226' || m == '1,0,80' || m == '1,0,79',
      ),
      isEmpty,
    );
  });

  testWidgets(
    'switched off: sideways two-finger scrolling is back and there is no Back / Forward',
    (tester) async {
      await setUpPad(tester);
      Settings.instance.update(() => Settings.instance.padSwipeNav = false);
      await twoFingers(tester, -200, 0);
      expect(agent.received.where((m) => m.startsWith('1,')), isEmpty);
      expect(frames('5,'), isNotEmpty, reason: 'sideways scroll');
    },
  );

  testWidgets('a two-finger tap is still a right click', (tester) async {
    await setUpPad(tester);
    final c = tester.getCenter(find.byType(TouchPad));
    final a = await tester.startGesture(c + const Offset(-30, 0));
    final b = await tester.startGesture(c + const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 40));
    await a.up();
    await b.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(agent.received, ['4,1,1', '4,1,0']);
  });
}
