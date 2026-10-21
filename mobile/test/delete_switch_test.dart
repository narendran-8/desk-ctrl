import 'package:deskctrl/connection.dart';
import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  test(
    'the layout has one Backspace/Del key when joined, and no separate Del',
    () {
      for (final functionRow in [true, false]) {
        final separate = layoutFor(functionRow: functionRow)
            .expand((r) => r)
            .toList();
        expect(separate.where((k) => k.label == 'Del'), hasLength(1));
        expect(separate.where((k) => k.label == 'Backspace'), hasLength(1));
        expect(separate.any((k) => k.isDeleteSwitch), isFalse);

        final joined = layoutFor(
          functionRow: functionRow,
          joinDelete: true,
        ).expand((r) => r).toList();
        expect(
          joined.where((k) => k.label == 'Del'),
          isEmpty,
          reason: 'functionRow=$functionRow',
        );
        expect(joined.where((k) => k.isDeleteSwitch), hasLength(1));
      }
    },
  );

  testWidgets(
    'swiping the joined key switches Backspace and Del; presses send the right key',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      Settings.instance.update(() => Settings.instance.joinDelete = true);
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      // A fake desktop agent and a real connection to it (real sockets need runAsync).
      final agent = await tester.runAsync(() => FakeAgent.start('tok'));
      Settings.instance.saveDevice(
        Device(
          id: 'd',
          name: 'D',
          host: '127.0.0.1',
          port: agent!.port,
          token: 'tok',
        ),
      );
      await tester.runAsync(() => Connection.instance.switchTo('d'));
      Future<void> deliver() => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await deliver();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: KeyboardScreen())),
      );
      expect(find.text('Backspace'), findsOneWidget);
      expect(find.text('Del'), findsNothing, reason: 'no separate Del key');
      expect(
        find.text('‹ Del ›'),
        findsOneWidget,
        reason: 'the other one is shown small',
      );

      // A tap sends Backspace (0x2A).
      await tester.tap(find.text('Backspace'));
      await tester.pump(const Duration(milliseconds: 300));
      await deliver();
      expect(agent.received, ['1,0,42', '2,0,42']);
      agent.received.clear();

      // Holding sends it down, and up when released.
      final hold = await tester.startGesture(
        tester.getCenter(find.text('Backspace')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await deliver();
      expect(agent.received, [
        '1,0,42',
      ], reason: 'down after the short delay, so holding repeats');
      await hold.up();
      await tester.pump();
      await deliver();
      expect(agent.received, ['1,0,42', '2,0,42']);
      agent.received.clear();

      // A horizontal swipe switches to Del and sends NOTHING (no stray delete).
      await tester.drag(find.text('Backspace'), const Offset(70, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await deliver();
      expect(
        agent.received,
        isEmpty,
        reason: 'swiping must not delete anything',
      );
      expect(find.text('Del'), findsOneWidget);
      expect(find.text('‹ Backspace ›'), findsOneWidget);

      // Now a tap sends Del (0x4C).
      await tester.tap(find.text('Del'));
      await tester.pump(const Duration(milliseconds: 300));
      await deliver();
      expect(agent.received, ['1,0,76', '2,0,76']);
      agent.received.clear();

      // Swiping the other way switches back.
      await tester.drag(find.text('Del'), const Offset(-70, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Backspace'), findsOneWidget);
      await tester.tap(find.text('Backspace'));
      await tester.pump(const Duration(milliseconds: 300));
      await deliver();
      expect(agent.received, ['1,0,42', '2,0,42']);

      await tester.runAsync(() async {
        await Connection.instance.disconnectAll();
        await agent.server.close(force: true);
      });
    },
  );
}
