import 'package:deskctrl/connection.dart';
import 'package:deskctrl/edge_zones.dart';
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
        id: 'zones',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('zones'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PadScreen())),
    );
  }

  Future<void> deliver(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );

  Rect padRect(WidgetTester tester) => tester.getRect(find.byType(TouchPad));

  /// One finger starting at [from] (relative to the pad's top-left), sliding by [delta].
  Future<void> slide(WidgetTester tester, Offset from, Offset delta) async {
    final g = await tester.startGesture(padRect(tester).topLeft + from);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(delta / 6);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
  }

  setUp(() {
    SwitchGuard.reset();
  });

  tearDown(() async {
    await Connection.instance.disconnectAll();
    await agent.server.close(force: true);
  });

  List<String> keys(Iterable<String> frames) => [
    for (final f in frames)
      if (!f.startsWith('3,')) f,
  ];
  bool moved(Iterable<String> frames) => frames.any((f) => f.startsWith('3,'));

  testWidgets('sliding up the left edge raises the volume, down lowers it', (
    tester,
  ) async {
    await setUpPad(tester);
    await slide(
      tester,
      const Offset(12, 200),
      const Offset(0, -90),
    ); // up 90 px = 4 steps
    await deliver(tester);
    expect(
      keys(agent.received),
      List.filled(4, ['1,128,233', '2,128,233']).expand((e) => e).toList(),
      reason: 'volume up x4',
    );
    expect(
      moved(agent.received),
      isFalse,
      reason: 'the cursor does not move while sliding an edge',
    );
    agent.received.clear();

    await slide(
      tester,
      const Offset(12, 120),
      const Offset(0, 45),
    ); // down 45 px = 2 steps
    await deliver(tester);
    expect(keys(agent.received), [
      '1,128,234',
      '2,128,234',
      '1,128,234',
      '2,128,234',
    ], reason: 'volume down x2');
    expect(
      find.text('Volume -'),
      findsOneWidget,
      reason: 'the pad says what it did',
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the right edge changes brightness', (tester) async {
    await setUpPad(tester);
    final w = padRect(tester).width;
    await slide(
      tester,
      Offset(w - 12, 200),
      const Offset(0, -50),
    ); // up: brighter x2
    await deliver(tester);
    expect(keys(agent.received), [
      '1,128,111',
      '2,128,111',
      '1,128,111',
      '2,128,111',
    ]);
    agent.received.clear();
    await slide(
      tester,
      Offset(w - 12, 100),
      const Offset(0, 25),
    ); // down: dimmer x1
    await deliver(tester);
    expect(keys(agent.received), ['1,128,112', '2,128,112']);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the top edge seeks: right = forward, left = backward', (
    tester,
  ) async {
    await setUpPad(tester);
    final w = padRect(tester).width;
    await slide(
      tester,
      Offset(w / 2 + 120, 14),
      const Offset(130, 0),
    ); // 130 px = 2 steps right
    await deliver(tester);
    expect(keys(agent.received), [
      '1,0,79',
      '2,0,79',
      '1,0,79',
      '2,0,79',
    ], reason: 'Right arrow x2 = forward');
    agent.received.clear();
    await slide(
      tester,
      Offset(w / 2 + 120, 14),
      const Offset(-70, 0),
    ); // 70 px = 1 step left
    await deliver(tester);
    expect(keys(agent.received), [
      '1,0,80',
      '2,0,80',
    ], reason: 'Left arrow = backward');
    expect(moved(agent.received), isFalse);
    expect(find.text('Backward'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('holding the >> / << ends keeps seeking until release', (
    tester,
  ) async {
    await setUpPad(tester);
    final rect = padRect(tester);
    for (final forward in [true, false]) {
      agent.received.clear();
      final g = await tester.startGesture(
        Offset(
          rect.left + rect.width / 2 + (forward ? 120 : -120),
          rect.top + 14,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await deliver(tester);
      expect(keys(agent.received), isEmpty, reason: 'not held long enough yet');
      await tester.pump(const Duration(milliseconds: 600));
      await deliver(tester);
      final code = forward ? '79' : '80';
      final downs = keys(agent.received).where((k) => k == '1,0,$code').length;
      expect(downs, greaterThanOrEqualTo(3), reason: 'repeats while held');
      await g.up();
      agent.received.clear();
      await tester.pump(const Duration(seconds: 1));
      await deliver(tester);
      expect(keys(agent.received), isEmpty, reason: 'stops on release');
      expect(moved(agent.received), isFalse);
    }
  });

  testWidgets('the message shows the real volume / brightness percentage', (
    tester,
  ) async {
    await setUpPad(tester);
    final r = padRect(tester);
    await slide(tester, Offset(20, r.height / 2), const Offset(0, -44));
    expect(
      find.text('Volume +'),
      findsOneWidget,
      reason: 'no number known yet',
    );
    agent.report(45, 60);
    await deliver(tester);
    await tester.pump();
    expect(find.text('Volume 45%'), findsOneWidget);
    // The report arrived outside the fake clock, so its timer runs in real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1400)),
    );
    await tester.pump();
    expect(
      find.textContaining('Volume'),
      findsNothing,
      reason: 'message goes away',
    );

    await slide(
      tester,
      Offset(r.width - 20, r.height / 2),
      const Offset(0, -44),
    );
    await tester.pump();
    expect(find.text('Brightness 60%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    agent.report(0, 60, muted: true);
    await deliver(tester);
    await slide(tester, Offset(20, r.height / 2), const Offset(0, 44));
    await tester.pump();
    expect(find.text('Volume muted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the end buttons skip to the next / previous track on a tap', (
    tester,
  ) async {
    await setUpPad(tester);
    final r = padRect(tester);
    final left = r.width * EdgeZones.topFrom, right = r.width * EdgeZones.topTo;
    for (final (x, code, label) in [
      (right - 15, '128,181', 'Next track'),
      (left + 15, '128,182', 'Previous track'),
    ]) {
      agent.received.clear();
      final g = await tester.startGesture(r.topLeft + Offset(x, 20));
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pump();
      await deliver(tester);
      expect(keys(agent.received), ['1,$code', '2,$code']);
      expect(find.text(label), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    }
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
  });

  testWidgets(
    'holding right on the << / >> icons seeks; the skip buttons are separate',
    (tester) async {
      await setUpPad(tester);
      final r = padRect(tester);
      final left = r.width * EdgeZones.topFrom,
          right = r.width * EdgeZones.topTo;
      // The centre of the >> icon sits one box in from the skip button at the very end.
      final x = right - EdgeZones.skipHalfWidth * 1.5;
      expect(EdgeZones.skipButton(Offset(x, 20), r.size), 0);
      expect(EdgeZones.skipButton(Offset(right - 20, 20), r.size), 1);
      expect(EdgeZones.skipButton(Offset(left + 78, 20), r.size), 0);
      final g = await tester.startGesture(r.topLeft + Offset(x, 20));
      // A held finger wobbles a little.
      await g.moveBy(const Offset(6, 3));
      await tester.pump(const Duration(milliseconds: 900));
      await deliver(tester);
      expect(
        keys(agent.received).where((k) => k == '1,0,79').length,
        greaterThanOrEqualTo(3),
      );
      await g.up();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('the seek speed setting changes how far a slide goes', (
    tester,
  ) async {
    await setUpPad(tester);
    Settings.instance.update(() => Settings.instance.seekSpeed = 5);
    final w = padRect(tester).width;
    await slide(tester, Offset(w / 2 + 120, 14), const Offset(130, 0));
    await deliver(tester);
    // 130 px at 60 / 2.5 = 24 px per step: 5 steps instead of 2.
    expect(keys(agent.received).where((k) => k == '1,0,79').length, 5);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('brightness on a computer that cannot change it says so', (
    tester,
  ) async {
    await setUpPad(tester);
    final r = padRect(tester);
    agent.report(45, 255); // volume known, no brightness
    await deliver(tester);
    await slide(
      tester,
      Offset(r.width - 20, r.height / 2),
      const Offset(0, -44),
    );
    await tester.pump();
    expect(
      find.text('Brightness not supported on this computer'),
      findsOneWidget,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1400)),
    );
    await tester.pump(const Duration(seconds: 2));
    // Volume is unaffected.
    await slide(tester, Offset(20, r.height / 2), const Offset(0, -44));
    await tester.pump();
    expect(find.text('Volume 45%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a tap on the volume strip mutes; a tap elsewhere still clicks', (
    tester,
  ) async {
    await setUpPad(tester);
    final r = padRect(tester);
    final g = await tester.startGesture(r.topLeft + Offset(20, r.height / 2));
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();
    await deliver(tester);
    expect(keys(agent.received), ['1,128,226', '2,128,226'], reason: 'mute');
    expect(find.text('Muted'), findsOneWidget);
    expect(
      find.byIcon(Icons.volume_off),
      findsOneWidget,
      reason: 'crossed out',
    );
    expect(find.byIcon(Icons.volume_up), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    final again = await tester.startGesture(
      r.topLeft + Offset(20, r.height / 2),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await again.up();
    await tester.pump();
    expect(find.text('Unmuted'), findsOneWidget);
    expect(
      find.byIcon(Icons.volume_up),
      findsOneWidget,
      reason: 'back to speaker',
    );
    await tester.pump(const Duration(seconds: 2));
    await deliver(tester);
    agent.received.clear();
    final c = await tester.startGesture(r.center);
    await tester.pump(const Duration(milliseconds: 50));
    await c.up();
    await tester.pump();
    await deliver(tester);
    expect(keys(agent.received), ['4,0,1', '4,0,0'], reason: 'plain click');
  });

  testWidgets(
    'the bottom edge switches windows: right = Alt+Tab, left = Alt+Shift+Tab',
    (tester) async {
      await setUpPad(tester);
      final r = padRect(tester);
      await slide(
        tester,
        Offset(r.width / 2 - 20, r.height - 14),
        const Offset(60, 0),
      );
      await deliver(tester);
      expect(keys(agent.received), [
        '1,0,226', // Alt down
        '1,0,43', '2,0,43', // Tab
        '2,0,226', // Alt up when the finger lifts
      ]);
      agent.received.clear();
      await tester.pump(const Duration(seconds: 2));
      await slide(
        tester,
        Offset(r.width / 2 + 20, r.height - 14),
        const Offset(-60, 0),
      );
      await deliver(tester);
      expect(keys(agent.received), [
        '1,0,226',
        '1,0,225', '1,0,43', '2,0,43', '2,0,225', // Shift+Tab
        '2,0,226',
      ]);
      expect(moved(agent.received), isFalse);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'holding on the bottom edge keeps the switcher open while you move',
    (tester) async {
      await setUpPad(tester);
      final r = padRect(tester);
      final g = await tester.startGesture(
        r.topLeft + Offset(r.width / 2, r.height - 14),
      );
      await tester.pump(
        const Duration(milliseconds: 600),
      ); // held still: switcher opens
      await deliver(tester);
      expect(keys(agent.received), [
        '1,0,226',
        '1,0,43',
        '2,0,43',
      ], reason: 'Alt stays down');
      agent.received.clear();
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(34, 0)); // 204 px = 4 more windows
        await tester.pump(const Duration(milliseconds: 16));
      }
      await deliver(tester);
      expect(
        keys(agent.received).where((k) => k == '1,0,43').length,
        4,
        reason: 'one Tab per window',
      );
      expect(
        keys(agent.received).contains('2,0,226'),
        isFalse,
        reason: 'Alt still held',
      );
      await g.up();
      await deliver(tester);
      expect(
        keys(agent.received).last,
        '2,0,226',
        reason: 'released on lift: switches',
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'tapping the middle of the bottom strip flips between windows and browser tabs',
    (tester) async {
      await setUpPad(tester);
      final r = padRect(tester);
      expect(find.byIcon(Icons.filter_none), findsOneWidget);

      final g = await tester.startGesture(
        r.topLeft + Offset(r.width / 2, r.height - 14),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pump();
      await deliver(tester);
      expect(
        keys(agent.received),
        isEmpty,
        reason: 'a toggle tap sends nothing',
      );
      expect(moved(agent.received), isFalse);
      expect(find.text('Switching browser tabs'), findsOneWidget);
      expect(find.byIcon(Icons.tab), findsOneWidget);
      expect(find.byIcon(Icons.filter_none), findsNothing);
      expect(Settings.instance.switchTabs, isTrue);
      await tester.pump(const Duration(seconds: 2));

      await slide(
        tester,
        Offset(r.width / 2 - 20, r.height - 14),
        const Offset(60, 0),
      );
      await deliver(tester);
      expect(keys(agent.received), [
        '1,0,224', // Ctrl down
        '1,0,43', '2,0,43', // Tab
        '2,0,224', // Ctrl up
      ], reason: 'Ctrl+Tab = next tab');
      expect(
        SwitchGuard.active,
        isTrue,
        reason: 'no auto-keyboard while switching tabs',
      );
      agent.received.clear();
      await tester.pump(const Duration(seconds: 2));

      await slide(
        tester,
        Offset(r.width / 2 + 20, r.height - 14),
        const Offset(-60, 0),
      );
      await deliver(tester);
      expect(keys(agent.received), [
        '1,0,224',
        '1,0,225', '1,0,43', '2,0,43', '2,0,225', // Shift+Tab
        '2,0,224',
      ], reason: 'Ctrl+Shift+Tab = previous tab');
      await tester.pump(const Duration(seconds: 2));

      // Tap again: back to windows.
      final g2 = await tester.startGesture(
        r.topLeft + Offset(r.width / 2, r.height - 14),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await g2.up();
      await tester.pump();
      expect(find.text('Switching windows'), findsOneWidget);
      expect(find.byIcon(Icons.filter_none), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'with browser tab switching off, the strip only switches windows',
    (tester) async {
      await setUpPad(tester);
      Settings.instance.update(() {
        Settings.instance.padTabSwitch = false;
        Settings.instance.switchTabs =
            true; // remembered, but not used while off
      });
      await tester.pump();
      final r = padRect(tester);
      expect(find.byIcon(Icons.filter_none), findsOneWidget);
      final g = await tester.startGesture(
        r.topLeft + Offset(r.width / 2, r.height - 14),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pump();
      await deliver(tester);
      expect(keys(agent.received), [
        '4,0,1',
        '4,0,0',
      ], reason: 'a plain click, no toggle');
      agent.received.clear();
      await slide(
        tester,
        Offset(r.width / 2 - 20, r.height - 14),
        const Offset(60, 0),
      );
      await deliver(tester);
      expect(keys(agent.received).first, '1,0,226', reason: 'Alt, not Ctrl');
      expect(
        SwitchGuard.active,
        isTrue,
        reason: 'an Alt+Tab swipe also makes the phone wait for the focus to settle',
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('the window switcher can be switched off', (tester) async {
    await setUpPad(tester);
    Settings.instance.update(() => Settings.instance.padWindows = false);
    await tester.pump();
    final r = padRect(tester);
    await slide(
      tester,
      Offset(r.width / 2, r.height - 14),
      const Offset(90, 0),
    );
    await deliver(tester);
    expect(keys(agent.received).contains('1,0,226'), isFalse);
    expect(moved(agent.received), isTrue, reason: 'plain touchpad again');
  });

  testWidgets(
    'the touchpad on / off switch is in Settings; the pad itself has no buttons on it',
    (tester) async {
      await setUpPad(tester);
      expect(
        find.byIcon(Icons.power_settings_new),
        findsNothing,
        reason: 'no power button on the pad',
      );
      expect(
        find.byIcon(Icons.more_vert),
        findsNothing,
        reason: 'no three-dots button on the pad',
      );

      Settings.instance.update(() => Settings.instance.padEnabled = false);
      await tester.pump();
      expect(find.text('Touchpad off'), findsOneWidget);
      await slide(tester, const Offset(300, 150), const Offset(120, 40));
      await deliver(tester);
      expect(
        moved(agent.received),
        isFalse,
        reason: 'a switched-off pad ignores touches',
      );

      Settings.instance.update(() => Settings.instance.padEnabled = true);
      await tester.pump();
      await slide(tester, const Offset(300, 150), const Offset(120, 40));
      await deliver(tester);
      expect(moved(agent.received), isTrue);
    },
  );

  testWidgets('the top edge can be set to skip tracks', (tester) async {
    await setUpPad(tester);
    Settings.instance.update(() => Settings.instance.padTopMode = 'track');
    await tester.pump();
    final w = padRect(tester).width;
    await slide(
      tester,
      Offset(w / 2 + 120, 14),
      const Offset(170, 0),
    ); // 80 px per step = 2 steps
    await deliver(tester);
    expect(keys(agent.received), [
      '1,128,181',
      '2,128,181',
      '1,128,181',
      '2,128,181',
    ], reason: 'next track x2');
    agent.received.clear();
    await slide(tester, Offset(w / 2 + 120, 14), const Offset(-90, 0));
    await deliver(tester);
    expect(keys(agent.received), [
      '1,128,182',
      '2,128,182',
    ], reason: 'previous track');
    expect(
      find.byIcon(Icons.skip_next),
      findsOneWidget,
      reason: 'the marks follow the mode',
    );
    expect(find.byIcon(Icons.fast_forward), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'a tap on the play / pause icon plays or pauses; a tap elsewhere on the strip clicks',
    (tester) async {
      await setUpPad(tester);
      final r = padRect(tester);

      final g = await tester.startGesture(r.topLeft + Offset(r.width / 2, 20));
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pump();
      await deliver(tester);
      expect(keys(agent.received), [
        '1,128,205',
        '2,128,205',
      ], reason: 'play / pause');
      expect(find.text('Play'), findsOneWidget);
      expect(
        find.byIcon(Icons.pause),
        findsOneWidget,
        reason: 'now offers pause',
      );
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      agent.received.clear();
      await tester.pump(const Duration(seconds: 1));

      final again = await tester.startGesture(
        r.topLeft + Offset(r.width / 2, 20),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await again.up();
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      expect(
        find.byIcon(Icons.play_arrow),
        findsOneWidget,
        reason: 'back to play',
      );
      expect(find.byIcon(Icons.pause), findsNothing);
      await deliver(tester);
      agent.received.clear();
      await tester.pump(const Duration(seconds: 1));

      final g2 = await tester.startGesture(
        r.topLeft + Offset(r.width / 2 + 150, 20),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await g2.up();
      await tester.pump();
      await deliver(tester);
      expect(keys(agent.received), [
        '4,0,1',
        '4,0,0',
      ], reason: 'a plain click away from the icon');
    },
  );

  testWidgets(
    'a tap on the brightness edge is still a click, and the middle of the pad moves the cursor',
    (tester) async {
      await setUpPad(tester);
      final g = await tester.startGesture(
        padRect(tester).topLeft + Offset(padRect(tester).width - 12, 200),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pump();
      await deliver(tester);
      expect(keys(agent.received), ['4,0,1', '4,0,0'], reason: 'left click');
      agent.received.clear();

      await slide(tester, const Offset(300, 150), const Offset(120, 40));
      await deliver(tester);
      expect(moved(agent.received), isTrue, reason: 'cursor moved');
      expect(
        agent.received.where((f) => f.startsWith('1,128')),
        isEmpty,
        reason: 'no media key from the middle',
      );
    },
  );

  testWidgets(
    'with the edge controls switched off the edges are just touchpad',
    (tester) async {
      await setUpPad(tester);
      Settings.instance.update(() => Settings.instance.padZones = false);
      await tester.pump();
      await slide(tester, const Offset(12, 200), const Offset(0, -90));
      await deliver(tester);
      expect(
        agent.received.where((f) => f.startsWith('1,128')),
        isEmpty,
        reason: 'no volume keys',
      );
      expect(
        moved(agent.received),
        isTrue,
        reason: 'the finger moves the cursor instead',
      );
      expect(
        find.byType(EdgeZoneMarks),
        findsNothing,
        reason: 'the markings are hidden too',
      );
    },
  );

  testWidgets('the markings show where the zones are', (tester) async {
    await setUpPad(tester);
    expect(find.byType(EdgeZoneMarks), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
    expect(find.byIcon(Icons.fast_forward), findsOneWidget, reason: 'forward');
    expect(find.byIcon(Icons.fast_rewind), findsOneWidget, reason: 'backward');
    expect(find.byIcon(Icons.play_arrow), findsOneWidget, reason: 'play first');
    expect(
      find.byIcon(Icons.pause),
      findsNothing,
      reason: 'only one of the two',
    );
    expect(
      find.byIcon(Icons.swipe),
      findsNothing,
      reason: 'the finger icon is gone',
    );
  });
}
