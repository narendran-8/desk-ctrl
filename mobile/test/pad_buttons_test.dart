import 'package:deskctrl/connection.dart';
import 'package:deskctrl/mouse_widgets.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PadScreen())),
    );
  }

  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);

  testWidgets('the Left and Right buttons are a slim bar, not a big block', (
    tester,
  ) async {
    await pump(tester);
    final left = rectOf(tester, find.byType(MouseButton).first);
    final right = rectOf(tester, find.byType(MouseButton).last);

    expect(left.height, padButtonBarHeight, reason: 'a fixed, slim height');
    expect(left.height, lessThan(48));
    expect(right.height, padButtonBarHeight);
    expect(left.top, right.top, reason: 'level with each other');
    expect(left.width, closeTo(right.width, 0.5), reason: 'equal halves');
    expect(right.left - left.right, 6, reason: 'a small neat gap between them');

    // The pad above takes all the rest of the room.
    final pad = rectOf(tester, find.byType(TouchPad));
    expect(pad.height, greaterThan(left.height * 4));
    expect(pad.bottom, lessThan(left.top));
  });

  testWidgets(
    'switching the buttons off in Settings gives the whole area to the pad',
    (tester) async {
      await pump(tester);
      final heightWith = rectOf(tester, find.byType(TouchPad)).height;
      expect(find.byType(MouseButton), findsNWidgets(2));

      Settings.instance.update(() => Settings.instance.padButtons = false);
      await tester.pump();
      expect(
        find.byType(MouseButton),
        findsNothing,
        reason: 'the buttons are gone',
      );
      expect(find.text('LEFT'), findsNothing);
      expect(find.text('RIGHT'), findsNothing);
      final heightWithout = rectOf(tester, find.byType(TouchPad)).height;
      expect(
        heightWithout,
        closeTo(heightWith + padButtonBarHeight + 6, 0.5),
        reason: 'the pad grew into the freed space',
      );

      Settings.instance.update(() => Settings.instance.padButtons = true);
      await tester.pump();
      expect(
        find.byType(MouseButton),
        findsNWidgets(2),
        reason: 'and they come back',
      );
    },
  );

  testWidgets('the slim buttons still press and release the mouse buttons', (
    tester,
  ) async {
    await pump(tester);
    // No computer is connected, so nothing is sent; the press state still shows.
    final g = await tester.startGesture(tester.getCenter(find.text('LEFT')));
    await tester.pump();
    final pressed = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MouseButton).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (pressed.decoration as BoxDecoration).color,
      const Color(0xFF4F8CFF),
      reason: 'lit while held',
    );
    await g.up();
    await tester.pump();
    final released = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MouseButton).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (released.decoration as BoxDecoration).color,
      isNot(const Color(0xFF4F8CFF)),
    );
    expect(Connection.instance.activeCount, 0);
  });
}
