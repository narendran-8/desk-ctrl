import 'dart:math' as math;

import 'package:deskctrl/app_theme.dart';
import 'package:deskctrl/connection.dart';
import 'package:deskctrl/edit_menu.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  FakeAgent? agentOrNull;
  FakeAgent agentNow() => agentOrNull!;

  Future<void> setUpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    agentOrNull = (await tester.runAsync(() => FakeAgent.start('tok')))!;
    Settings.instance.saveDevice(
      Device(
        id: 'em',
        name: 'PC',
        host: '127.0.0.1',
        port: agentOrNull!.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('em'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: EditMenuButton()),
        ),
      ),
    );
  }

  tearDown(() async {
    await Connection.instance.disconnectAll();
    await agentOrNull?.server.close(force: true);
    agentOrNull = null;
  });

  /// Open the menu, tap one wedge. The menu stays open (the default), so close it again.
  Future<void> tapWedge(
    WidgetTester tester,
    Offset origin,
    int ring,
    int i, {
    int sx = 1,
    int sy = 1,
  }) async {
    await tester.tap(find.byType(EditMenuButton));
    await tester.pump();
    expect(find.byType(EditFan), findsOneWidget, reason: 'the menu is open');
    agentNow().received.clear();
    await tester.tapAt(EditFan.centreOf(origin, sx, sy, ring, i));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    expect(
      find.byType(EditFan),
      findsOneWidget,
      reason: 'it stays open for the next tap',
    );
    await tester.tapAt(const Offset(700, 300)); // outside the rings: close
    await tester.pump();
    expect(find.byType(EditFan), findsNothing);
  }

  test('three rows: edit shortcuts, terminal copy / paste + keys, refresh', () {
    expect(editActions.map((a) => a.label), [
      'Copy',
      'Cut',
      'Paste',
      'Undo',
      'Select all',
    ]);
    expect(terminalActions.map((a) => a.label), [
      'Terminal copy',
      'Terminal paste',
      'Enter',
      'Backspace',
      'Delete',
    ]);
    expect(refreshActions.map((a) => a.label), [
      'Refresh',
      'Open terminal',
      'Close application',
    ]);
    expect(editRings.length, 3);
    // The rings do not overlap and are inside each other.
    for (var r = 0; r < editRings.length - 1; r++) {
      expect(EditFan.outerRadius(r), lessThan(EditFan.innerRadius(r + 1)));
    }
    expect(
      EditFan.reach,
      lessThanOrEqualTo(300),
      reason: 'fits in a phone held sideways (360 high) and held upright (360 wide)',
    );
  });

  test('which wedge is under a point', () {
    (int, int)? at(double degrees, double r) {
      final a = degrees * math.pi / 180;
      return EditFan.wedgeAt(Offset(math.cos(a) * r, math.sin(a) * r));
    }

    // Inner ring: five wedges of 18 degrees.
    for (var i = 0; i < 5; i++) {
      expect(at(i * 18 + 9, 100), (0, i), reason: 'inner wedge $i');
      expect(at(i * 18 + 9, 200), (1, i), reason: 'outer wedge $i');
    }
    expect(at(5, 20), isNull, reason: 'inside the hole');
    expect(at(5, 130), isNull, reason: 'between the rings');
    expect(at(5, 214), isNull, reason: 'between the rings');
    // Third row: three options share the quarter.
    expect(at(9, 260), (2, 0), reason: 'Refresh');
    expect(at(40, 260), (2, 1), reason: 'Open terminal');
    expect(at(80, 260), (2, 2), reason: 'Close application');
    expect(at(5, 400), isNull, reason: 'outside the rings');
    expect(
      EditFan.wedgeAt(const Offset(-100, 50)),
      isNull,
      reason: 'behind the button',
    );
    expect(
      EditFan.wedgeAt(const Offset(100, -50)),
      isNull,
      reason: 'above the button',
    );
  });

  testWidgets('every wedge sends its keys', (tester) async {
    await setUpApp(tester);
    final origin = tester.getCenter(find.byType(EditMenuButton));
    // Key codes: Ctrl 224, Shift 225; C 6, X 27, V 25, Z 29, A 4; Enter 40, Backspace 42, Delete 76.
    final expected = <(int, int), List<String>>{
      (0, 0): ['1,0,224', '1,0,6', '2,0,6', '2,0,224'], // Ctrl+C
      (0, 1): ['1,0,224', '1,0,27', '2,0,27', '2,0,224'], // Ctrl+X
      (0, 2): ['1,0,224', '1,0,25', '2,0,25', '2,0,224'], // Ctrl+V
      (0, 3): ['1,0,224', '1,0,29', '2,0,29', '2,0,224'], // Ctrl+Z
      (0, 4): ['1,0,224', '1,0,4', '2,0,4', '2,0,224'], // Ctrl+A
      (1, 0): [
        '1,0,224',
        '1,0,225',
        '1,0,6',
        '2,0,6',
        '2,0,225',
        '2,0,224',
      ], // Ctrl+Shift+C
      (1, 1): [
        '1,0,224',
        '1,0,225',
        '1,0,25',
        '2,0,25',
        '2,0,225',
        '2,0,224',
      ], // Ctrl+Shift+V
      (1, 2): ['1,0,40', '2,0,40'], // Enter
      (1, 3): ['1,0,42', '2,0,42'], // Backspace
      (1, 4): ['1,0,76', '2,0,76'], // Delete
      (2, 0): ['1,0,62', '2,0,62'], // Refresh = F5
      (2, 2): ['1,0,226', '1,0,61', '2,0,61', '2,0,226'], // Alt+F4
      (2, 1): [
        '1,0,224',
        '1,0,226',
        '1,0,23',
        '2,0,23',
        '2,0,226',
        '2,0,224',
      ], // Ctrl+Alt+T
    };
    for (final e in expected.entries) {
      await tapWedge(tester, origin, e.key.$1, e.key.$2);
      expect(
        agentNow().received,
        e.value,
        reason: editRings[e.key.$1][e.key.$2].label,
      );
    }
  });

  testWidgets(
    'a tap outside the rings closes the menu without sending anything',
    (tester) async {
      await setUpApp(tester);
      await tester.tap(find.byType(EditMenuButton));
      await tester.pumpAndSettle();
      await tester.tapAt(
        const Offset(700, 300),
      ); // far from the rings (the view is 820 x 360)
      await tester.pumpAndSettle();
      expect(find.byType(EditFan), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      expect(agentNow().received, isEmpty);
    },
  );

  testWidgets(
    'black and white: the inner ring is white, the outer ring black, the wedge under the finger swaps',
    (tester) async {
      await setUpApp(tester);
      await tester.tap(find.byType(EditMenuButton));
      await tester.pumpAndSettle();
      // Pictures: black on the white ring, white on the black ring.
      Color iconColor(IconData d) =>
          tester.widget<Icon>(find.byIcon(d).first).color!;
      expect(iconColor(Icons.content_cut), const Color(0xFF000000));
      expect(iconColor(Icons.keyboard_return), const Color(0xFFFFFFFF));
      // Pressing on a wedge swaps its colours; the label appears.
      final origin = tester.getCenter(find.byType(EditMenuButton));
      final g = await tester.startGesture(EditFan.centreOf(origin, 1, 1, 0, 1));
      await tester.pump();
      expect(
        iconColor(Icons.content_cut),
        const Color(0xFFFFFFFF),
        reason: 'the pressed wedge turns black',
      );
      expect(find.text('Cut'), findsOneWidget);
      await g.up(); // lifting on it runs it and closes the menu
      await tester.pumpAndSettle();
    },
  );

  test('the rings open towards the middle of the screen, from any corner', () {
    const screen = Size(800, 360);
    expect(EditFan.directionFor(const Offset(50, 30), screen), (
      1,
      1,
    ), reason: 'top left: right + down');
    expect(EditFan.directionFor(const Offset(750, 30), screen), (
      -1,
      1,
    ), reason: 'top right: left + down');
    expect(EditFan.directionFor(const Offset(50, 330), screen), (
      1,
      -1,
    ), reason: 'bottom left: right + up');
    expect(EditFan.directionFor(const Offset(750, 330), screen), (-1, -1));

    for (final (sx, sy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
      for (var ring = 0; ring < editRings.length; ring++) {
        for (var w = 0; w < editRings[ring].length; w++) {
          final p = EditFan.centreOf(Offset.zero, sx, sy, ring, w);
          expect(EditFan.wedgeAt(p, sx: sx, sy: sy), (
            ring,
            w,
          ), reason: 'ring $ring wedge $w opening ($sx, $sy)');
          expect(p.dx.sign, sx.toDouble());
          expect(p.dy.sign, sy.toDouble());
        }
      }
      expect(
        EditFan.wedgeAt(Offset(-100.0 * sx, -100.0 * sy), sx: sx, sy: sy),
        isNull,
      );
    }
  });

  testWidgets('the rings fit on screen whichever way the phone is held', (
    tester,
  ) async {
    await setUpApp(tester);
    for (final (w, h, at) in [
      (1640.0, 720.0, Alignment.topLeft),
      (
        1640.0,
        720.0,
        Alignment.topRight,
      ), // the other landscape: the bar is on the right
      (720.0, 1640.0, Alignment.topLeft), // portrait
      (720.0, 1640.0, Alignment.topRight),
    ]) {
      tester.view.physicalSize = Size(w, h);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(alignment: at, child: const EditMenuButton()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(EditMenuButton));
      await tester.pumpAndSettle();
      final fan = find.byType(EditFan);
      expect(fan, findsOneWidget, reason: 'open at $at in ${w}x$h');
      final widget = tester.widget<EditFan>(fan);
      final screen = Size(w / 2, h / 2);
      for (var ring = 0; ring < editRings.length; ring++) {
        for (var i = 0; i < editRings[ring].length; i++) {
          final p = EditFan.centreOf(
            widget.origin,
            widget.sx,
            widget.sy,
            ring,
            i,
          );
          expect(
            p.dx > 0 && p.dx < screen.width && p.dy > 0 && p.dy < screen.height,
            isTrue,
            reason: 'ring $ring wedge $i at $at in ${w}x$h: $p of $screen',
          );
        }
      }
      expect(tester.takeException(), isNull, reason: 'no overflow');
      await tester.tapAt(const Offset(5, 340)); // outside the rings
      await tester.pumpAndSettle();
      expect(find.byType(EditFan), findsNothing);
    }
  });

  testWidgets('turning the phone while the menu is open closes it', (
    tester,
  ) async {
    await setUpApp(tester);
    await tester.tap(find.byType(EditMenuButton));
    await tester.pumpAndSettle();
    expect(find.byType(EditFan), findsOneWidget);
    tester.view.physicalSize = const Size(720, 1640);
    await tester.pumpAndSettle();
    expect(
      find.byType(EditFan),
      findsNothing,
      reason: 'it would be left where the button used to be',
    );
  });

  group('hold the button, drag to an option, lift to run it', () {
    testWidgets(
      'hold expands the menu; lifting on a wedge runs it and folds the menu away',
      (tester) async {
        await setUpApp(tester);
        final origin = tester.getCenter(find.byType(EditMenuButton));
        final g = await tester.startGesture(origin);
        expect(
          find.byType(EditFan),
          findsNothing,
          reason: 'not yet: it is still a tap',
        );
        await tester.pump(
          EditMenuButton.holdTime + const Duration(milliseconds: 50),
        );
        expect(find.byType(EditFan), findsOneWidget, reason: 'held: expanded');
        expect(
          find.byType(Tooltip),
          findsNothing,
          reason: 'no popup description',
        );
        final disc = find.byKey(const Key('editButtonActive'));
        expect(
          disc,
          findsOneWidget,
          reason: 'the button is drawn in the accent colour',
        );
        expect(
          (tester.widget<Container>(disc).decoration as BoxDecoration).color,
          AppTheme.colors('soft', AppTheme.defaultAccent).accent,
        );
        expect(tester.getCenter(disc), origin);

        await g.moveTo(EditFan.centreOf(origin, 1, 1, 1, 2)); // Enter
        await tester.pump();
        expect(
          find.text('Enter'),
          findsOneWidget,
          reason: 'the option under the finger is named',
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        expect(
          agentNow().received,
          isEmpty,
          reason: 'nothing is sent until the finger lifts',
        );

        await g.moveTo(
          EditFan.centreOf(origin, 1, 1, 1, 3),
        ); // slid on to Backspace
        await tester.pump();
        expect(find.text('Backspace'), findsOneWidget);

        await g.up();
        await tester.pump();
        expect(
          find.byType(EditFan),
          findsNothing,
          reason: 'lifting folds the menu away',
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        expect(agentNow().received, [
          '1,0,42',
          '2,0,42',
        ], reason: 'Backspace, the one under the finger');
      },
    );

    testWidgets('lifting anywhere else just folds the menu away', (
      tester,
    ) async {
      await setUpApp(tester);
      final origin = tester.getCenter(find.byType(EditMenuButton));
      final g = await tester.startGesture(origin);
      await tester.pump(
        EditMenuButton.holdTime + const Duration(milliseconds: 50),
      );
      await g.moveTo(EditFan.centreOf(origin, 1, 1, 0, 1));
      await tester.pump();
      await g.moveTo(const Offset(700, 300));
      await tester.pump();
      expect(find.byType(EditFan), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(find.byType(EditFan), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      expect(agentNow().received, isEmpty);
    });

    testWidgets(
      'holding and lifting without leaving the button leaves the menu open to tap options',
      (tester) async {
        await setUpApp(tester);
        final origin = tester.getCenter(find.byType(EditMenuButton));
        final g = await tester.startGesture(origin);
        await tester.pump(
          EditMenuButton.holdTime + const Duration(milliseconds: 50),
        );
        await g.up();
        await tester.pump();
        expect(
          find.byType(EditFan),
          findsOneWidget,
          reason: 'still open: a press that opened it',
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        expect(agentNow().received, isEmpty, reason: 'nothing was sent');
        await tester.tapAt(EditFan.centreOf(origin, 1, 1, 1, 2)); // Enter
        await tester.pump();
        expect(
          find.byType(EditFan),
          findsOneWidget,
          reason: 'stays for the next tap',
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        expect(agentNow().received, ['1,0,40', '2,0,40']);
        await tester.tapAt(const Offset(700, 300));
        await tester.pump();
      },
    );

    testWidgets('a quick tap opens the menu and leaves it open', (
      tester,
    ) async {
      await setUpApp(tester);
      await tester.tap(find.byType(EditMenuButton));
      await tester.pump();
      expect(find.byType(EditFan), findsOneWidget);
      await tester.tapAt(const Offset(700, 300));
      await tester.pump();
      expect(find.byType(EditFan), findsNothing);
    });

    testWidgets('turning the phone while holding folds the menu away', (
      tester,
    ) async {
      await setUpApp(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(EditMenuButton)),
      );
      await tester.pump(
        EditMenuButton.holdTime + const Duration(milliseconds: 50),
      );
      expect(find.byType(EditFan), findsOneWidget);
      tester.view.physicalSize = const Size(720, 1640);
      await tester.pump();
      await tester.pump();
      expect(find.byType(EditFan), findsNothing);
      await g.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'from the top-right corner it opens leftwards and the drag works the same',
      (tester) async {
        await setUpApp(tester);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: EditMenuButton(),
              ),
            ),
          ),
        );
        final origin = tester.getCenter(find.byType(EditMenuButton));
        final g = await tester.startGesture(origin);
        await tester.pump(
          EditMenuButton.holdTime + const Duration(milliseconds: 50),
        );
        final fan = tester.widget<EditFan>(find.byType(EditFan));
        expect((fan.sx, fan.sy), (-1, 1));
        await g.moveTo(EditFan.centreOf(origin, -1, 1, 0, 2)); // Paste
        await g.up();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        expect(agentNow().received, ['1,0,224', '1,0,25', '2,0,25', '2,0,224']);
      },
    );

    testWidgets('a touch on the menu does not reach what is under it', (
      tester,
    ) async {
      var underneath = 0;
      await setUpApp(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GestureDetector(
                  onTap: () => underneath++,
                  child: const SizedBox.expand(),
                ),
                const Align(
                  alignment: Alignment.topLeft,
                  child: EditMenuButton(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(EditMenuButton));
      await tester.pump();
      await tester.tapAt(const Offset(700, 300));
      await tester.pump();
      expect(find.byType(EditFan), findsNothing);
      expect(
        underneath,
        0,
        reason: 'the tap that closed the menu was not also a tap on the screen below',
      );
    });
  });

  group(
    'the menu stays open for repeated taps, and holding Backspace repeats it',
    () {
      int presses(String code) =>
          agentNow().received.where((f) => f == '1,0,$code').length;

      testWidgets('Backspace, Delete and Enter can be tapped again and again', (
        tester,
      ) async {
        await setUpApp(tester);
        final origin = tester.getCenter(find.byType(EditMenuButton));
        await tester.tap(find.byType(EditMenuButton));
        await tester.pump();
        for (final (wedge, code) in [(3, '42'), (4, '76'), (2, '40')]) {
          for (var i = 0; i < 3; i++) {
            await tester.tapAt(EditFan.centreOf(origin, 1, 1, 1, wedge));
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          expect(
            presses(code),
            3,
            reason: 'three taps = three presses of key $code',
          );
        }
        expect(
          find.byType(EditFan),
          findsOneWidget,
          reason: 'nine taps and it is still open',
        );
        await tester.tapAt(const Offset(700, 300));
        await tester.pump();
      });

      testWidgets(
        'holding a finger on Backspace repeats it until you lift (delete a paragraph)',
        (tester) async {
          await setUpApp(tester);
          final origin = tester.getCenter(find.byType(EditMenuButton));
          await tester.tap(find.byType(EditMenuButton));
          await tester.pump();
          final g = await tester.startGesture(
            EditFan.centreOf(origin, 1, 1, 1, 3),
          );
          await tester.pump(const Duration(milliseconds: 250));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          expect(
            presses('42'),
            0,
            reason: 'a short hold is still just a tap: nothing yet',
          );
          for (var i = 0; i < 40; i++) {
            await tester.pump(
              const Duration(milliseconds: 50),
            ); // 2 seconds of holding
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          final held = presses('42');
          expect(
            held,
            greaterThan(25),
            reason: 'repeated while held: $held presses',
          );
          expect(
            find.byType(EditFan),
            findsOneWidget,
            reason: 'the menu does not close while you hold',
          );

          await g.up();
          await tester.pump();
          agentNow().received.clear();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          expect(
            presses('42'),
            0,
            reason: 'lifting stops it, and the lift is not one more press',
          );
          expect(
            find.byType(EditFan),
            findsOneWidget,
            reason: 'still open afterwards',
          );
          await tester.tapAt(const Offset(700, 300));
          await tester.pump();
        },
      );

      testWidgets('a quick tap on Backspace is exactly one press', (
        tester,
      ) async {
        await setUpApp(tester);
        final origin = tester.getCenter(find.byType(EditMenuButton));
        await tester.tap(find.byType(EditMenuButton));
        await tester.pump();
        final g = await tester.startGesture(
          EditFan.centreOf(origin, 1, 1, 1, 3),
        );
        await tester.pump(const Duration(milliseconds: 120));
        await g.up();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        expect(presses('42'), 1);
        await tester.tapAt(const Offset(700, 300));
        await tester.pump();
      });

      testWidgets('sliding off the option while holding stops the repeat', (
        tester,
      ) async {
        await setUpApp(tester);
        final origin = tester.getCenter(find.byType(EditMenuButton));
        await tester.tap(find.byType(EditMenuButton));
        await tester.pump();
        final g = await tester.startGesture(
          EditFan.centreOf(origin, 1, 1, 1, 3),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        expect(presses('42'), greaterThan(2), reason: 'it was repeating');
        await g.moveTo(const Offset(700, 300));
        await tester.pump();
        agentNow().received.clear();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        expect(presses('42'), 0, reason: 'stopped');
        await g.up();
        await tester.pump();
      });

      testWidgets('options that must not repeat (Paste, Copy ...) do not', (
        tester,
      ) async {
        await setUpApp(tester);
        final origin = tester.getCenter(find.byType(EditMenuButton));
        await tester.tap(find.byType(EditMenuButton));
        await tester.pump();
        final g = await tester.startGesture(
          EditFan.centreOf(origin, 1, 1, 0, 2),
        ); // Paste
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await g.up();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        expect(presses('25'), 1, reason: 'one paste, however long it was held');
        await tester.tapAt(const Offset(700, 300));
        await tester.pump();
      });

      testWidgets(
        'left open and untouched, the menu folds away by itself; using it keeps it open',
        (tester) async {
          await setUpApp(tester);
          final origin = tester.getCenter(find.byType(EditMenuButton));
          await tester.tap(find.byType(EditMenuButton));
          await tester.pump();
          await tester.pump(const Duration(seconds: 4));
          expect(find.byType(EditFan), findsOneWidget, reason: 'not yet');
          await tester.tapAt(EditFan.centreOf(origin, 1, 1, 1, 3));
          await tester.pump(const Duration(seconds: 4));
          expect(
            find.byType(EditFan),
            findsOneWidget,
            reason: '4 s after the last tap',
          );
          await tester.pump(const Duration(seconds: 3));
          expect(
            find.byType(EditFan),
            findsNothing,
            reason: 'folded away after the idle time',
          );
        },
      );

      testWidgets(
        'with "keep the edit menu open" off, an option closes the menu',
        (tester) async {
          await setUpApp(tester);
          Settings.instance.update(
            () => Settings.instance.editMenuStayOpen = false,
          );
          final origin = tester.getCenter(find.byType(EditMenuButton));
          await tester.tap(find.byType(EditMenuButton));
          await tester.pump();
          await tester.tapAt(EditFan.centreOf(origin, 1, 1, 1, 2)); // Enter
          await tester.pump();
          expect(find.byType(EditFan), findsNothing);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          expect(presses('40'), 1);
        },
      );
    },
  );
}
