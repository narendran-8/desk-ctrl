import 'package:deskctrl/connection.dart';
import 'package:deskctrl/edge_zones.dart';
import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  late FakeAgent agent;

  Future<void> start(WidgetTester tester, {bool auto = true}) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    Settings.instance.update(() {
      Settings.instance.modeOrder = ['pad', 'keyboard', 'mouse'];
      Settings.instance.padTab = true;
      Settings.instance.autoKeyboard = auto;
    });
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
    Settings.instance.saveDevice(
      Device(
        id: 'af',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('af'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpWidget(const MaterialApp(home: Home()));
    await tester.pump();
  }

  setUp(() {
    SwitchGuard.reset();
    // A click from the test before must not count for this one.
    Connection.instance.lastClickAt = DateTime.fromMillisecondsSinceEpoch(0);
  });

  tearDown(() async {
    await Connection.instance.disconnectAll();
    await agent.server.close(force: true);
  });

  Future<void> wait(WidgetTester tester, int ms) async {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: ms)),
    );
    await tester.pump(Duration(milliseconds: ms));
  }

  Future<void> click(WidgetTester tester) async {
    Connection.instance.click(0); // a click with the pointer
    await tester.pump();
  }

  bool onKeyboard() => find.byType(KeyboardScreen).evaluate().isNotEmpty;
  bool onPad() => find.byType(PadScreen).evaluate().isNotEmpty;

  group('option 1: a typeable field opens the keyboard by itself', () {
    testWidgets('typeable -> keyboard', (tester) async {
      await start(tester);
      expect(onPad(), isTrue);
      agent.textFocus();
      await wait(tester, 300);
      expect(onKeyboard(), isTrue);
    });

    testWidgets('not typeable -> stays on the touchpad', (tester) async {
      await start(tester);
      agent.textFocus(typeable: false);
      await wait(tester, 300);
      expect(onPad(), isTrue);
    });

    testWidgets('an older agent that sends just the focus frame still works', (
      tester,
    ) async {
      await start(tester);
      agent.textFocus(old: true);
      await wait(tester, 300);
      expect(onKeyboard(), isTrue);
    });

    testWidgets(
      'switching windows or tabs: waits, and the place it lands decides (typeable)',
      (tester) async {
        await start(tester);
        SwitchGuard.touch(); // the bottom slider is being used
        agent.textFocus(typeable: false); // passing a page ...
        await wait(tester, 100);
        agent.textFocus(); // ... landing on a window with a text field
        await wait(tester, 300);
        expect(onPad(), isTrue, reason: 'waiting for the focus to settle');
        await wait(tester, 900);
        expect(onKeyboard(), isTrue);
      },
    );

    testWidgets(
      'switching windows or tabs: landing on a non-typeable place stays',
      (tester) async {
        await start(tester);
        SwitchGuard.touch();
        agent.textFocus(); // a window on the way had a field ...
        await wait(tester, 100);
        agent.textFocus(typeable: false); // ... the one it ended on has none
        await wait(tester, 1300);
        expect(onPad(), isTrue);
      },
    );

    testWidgets('the setting can turn it off completely', (tester) async {
      await start(tester, auto: false);
      agent.textFocus();
      await wait(tester, 300);
      expect(onPad(), isTrue);
    });
  });

  group('option 2: only a click you make opens the keyboard', () {
    Future<void> opt2(WidgetTester tester) async {
      await start(tester);
      Settings.instance.update(
        () => Settings.instance.autoKeyboardOnClick = true,
      );
    }

    testWidgets('a typeable field that appears by itself does not open it', (
      tester,
    ) async {
      await opt2(tester);
      agent.textFocus(); // a window / tab with a text field came to the front
      await wait(tester, 2000);
      expect(onPad(), isTrue);
    });

    testWidgets(
      'switching windows with a typeable field, nothing clicked: stays',
      (tester) async {
        await opt2(tester);
        SwitchGuard.touch();
        agent.textFocus();
        await wait(tester, 2000);
        expect(onPad(), isTrue);
      },
    );

    testWidgets(
      'then you click in the field (it already had the focus): keyboard opens',
      (tester) async {
        await opt2(tester);
        agent.textFocus(); // the window in front has a focused text field; phone stays put
        await wait(tester, 500);
        expect(onPad(), isTrue);
        await click(tester);
        await wait(tester, 600);
        expect(onKeyboard(), isTrue);
      },
    );

    testWidgets(
      'a click that puts the focus into a field (focus event after it): opens',
      (tester) async {
        await opt2(tester);
        agent.textFocus(typeable: false);
        await wait(tester, 200);
        await click(tester);
        agent.textFocus(); // the click gave a text field the focus
        await wait(tester, 200);
        expect(onKeyboard(), isTrue);
      },
    );

    testWidgets(
      'a click on something that is not a field stays on the touchpad',
      (tester) async {
        await opt2(tester);
        agent.textFocus(typeable: false);
        await wait(tester, 200);
        await click(tester);
        await wait(tester, 800);
        expect(onPad(), isTrue);
      },
    );

    testWidgets(
      'a click that moves the focus away from the field does not open it',
      (tester) async {
        await opt2(tester);
        agent.textFocus(); // field focused in the window in front
        await wait(tester, 200);
        await click(tester);
        agent.textFocus(
          typeable: false,
        ); // ... but the click landed on a button, focus left
        await wait(tester, 900);
        expect(onPad(), isTrue);
      },
    );
  });
}
