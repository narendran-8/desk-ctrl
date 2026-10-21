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
        id: 'shot',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('shot'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PadScreen())),
    );
  }

  Future<void> deliver(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );

  /// Puts [fingers] on the pad, moves them all by [delta], and lifts them.
  Future<void> swipe(
    WidgetTester tester,
    Offset delta, {
    int fingers = 3,
  }) async {
    final centre = tester.getCenter(find.byType(TouchPad));
    final gestures = <TestGesture>[];
    for (var i = 0; i < fingers; i++) {
      gestures.add(
        await tester.startGesture(
          centre + Offset(-60.0 + i * 60, 0),
          pointer: 10 + i,
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 30));
    for (var step = 1; step <= 4; step++) {
      for (final g in gestures) {
        await g.moveBy(delta / 4);
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    for (final g in gestures) {
      await g.up();
    }
    await tester.pump();
  }

  tearDown(() async {
    await Connection.instance.disconnectAll();
    await agent.server.close(force: true);
  });

  const printScreenDown = '1,0,70', printScreenUp = '2,0,70'; // HID usage 0x46

  testWidgets('three fingers swiping down take a screenshot on the computer', (
    tester,
  ) async {
    await setUpPad(tester);
    await swipe(tester, const Offset(0, 160));
    await deliver(tester);
    expect(agent.received, [printScreenDown, printScreenUp]);
    expect(
      find.text('Screenshot taken on the computer'),
      findsOneWidget,
      reason: 'you see that it happened',
    );
    await tester.pump(const Duration(seconds: 3)); // let the message go away
  });

  testWidgets('with the switch off the same swipe does nothing', (
    tester,
  ) async {
    await setUpPad(tester);
    Settings.instance.update(() => Settings.instance.screenshotSwipe = false);
    await tester.pump();
    await swipe(tester, const Offset(0, 160));
    await deliver(tester);
    expect(agent.received, isEmpty, reason: 'no Print Screen');
    expect(find.text('Screenshot taken on the computer'), findsNothing);
    expect(
      find.textContaining('swipe down = screenshot'),
      findsNothing,
      reason: 'the hint no longer mentions it',
    );
  });

  testWidgets('the other three-finger gestures are unchanged', (tester) async {
    await setUpPad(tester);

    await swipe(tester, const Offset(0, -160)); // up: overview (Super)
    await deliver(tester);
    expect(agent.received, ['1,0,227', '2,0,227']);
    agent.received.clear();

    await swipe(
      tester,
      const Offset(160, 0),
    ); // sideways: workspace (Ctrl+Alt+arrow)
    await deliver(tester);
    expect(agent.received, contains('1,0,224'), reason: 'Ctrl');
    expect(agent.received, contains('1,0,226'), reason: 'Alt');
    expect(agent.received, isNot(contains(printScreenDown)));
    agent.received.clear();

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('two fingers moving down scroll, they do not take a screenshot', (
    tester,
  ) async {
    await setUpPad(tester);
    await swipe(tester, const Offset(0, 160), fingers: 2);
    await deliver(tester);
    expect(agent.received, isNot(contains(printScreenDown)));
    expect(find.text('Screenshot taken on the computer'), findsNothing);
  });

  testWidgets('a three-finger tap is still a middle click', (tester) async {
    await setUpPad(tester);
    final centre = tester.getCenter(find.byType(TouchPad));
    final gs = [
      for (var i = 0; i < 3; i++)
        await tester.startGesture(
          centre + Offset(-60.0 + i * 60, 0),
          pointer: 20 + i,
        ),
    ];
    await tester.pump(const Duration(milliseconds: 60));
    for (final g in gs) {
      await g.up();
    }
    await tester.pump();
    await deliver(tester);
    expect(agent.received, [
      '4,2,1',
      '4,2,0',
    ], reason: 'middle button down and up');
  });
}
