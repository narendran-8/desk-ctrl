import 'package:deskctrl/connection.dart';
import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/mobile_screen.dart';
import 'package:deskctrl/modes.dart';
import 'package:deskctrl/modes_editor.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/phone_media.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  test('portrait Mobile keyboard includes every common punctuation key', () {
    expect(portraitKeyboardLayout, hasLength(6));
    final punctuation = portraitKeyboardLayout[4];
    expect(
      [
        [for (final key in punctuation) key.label],
        [for (final key in punctuation) key.alt],
      ],
      [
        [r'`', '-', '=', '[', ']', r'\', ';', "'", ',', '.', '/'],
        ['~', '_', '+', '{', '}', '|', ':', '"', '<', '>', '?'],
      ],
    );
  });

  testWidgets('portrait media icons send play/pause and next to the computer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(720, 1640);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
    addTearDown(() async {
      await Connection.instance.disconnectAll();
      await agent.server.close(force: true);
    });
    Settings.instance.saveDevice(
      Device(
        id: 'portrait-media',
        name: 'Test computer',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('portrait-media'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MobileScreen())),
    );
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.play_arrow)));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    expect(agent.received, containsAllInOrder(['1,128,205', '2,128,205']));
    agent.received.clear();
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.skip_next)));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    expect(agent.received, containsAllInOrder(['1,128,181', '2,128,181']));

    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(PhoneMedia.channel, (call) async {
      calls.add('${call.method}:${call.arguments}');
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(PhoneMedia.channel, null),
    );
    await tester.tap(find.byTooltip('Mobile media off'));
    await tester.pump();
    expect(find.byTooltip('Mobile media on'), findsOneWidget);
    agent.received.clear();
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.pause)));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.skip_next)));
    await tester.pump();
    expect(calls, containsAll(['action:playPause', 'action:next']));
    expect(agent.received.where((f) => f.startsWith('1,128')), isEmpty);
  });

  for (final (size, compact) in [
    (const Size(1640, 720), false),
    (const Size(720, 1640), true),
  ]) {
    testWidgets(
      'mobile screen fits ${compact ? 'portrait' : 'landscape'} and swaps pad with keys',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await Settings.instance.load();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: MobileScreen())),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(TouchPad), findsOneWidget);
        expect(find.byType(KeyboardScreen), findsOneWidget);
        expect(
          tester.widget<KeyboardScreen>(find.byType(KeyboardScreen)).compact,
          compact,
        );
        expect(find.byTooltip('Rotate Mobile screen'), findsOneWidget);
        final rotate = find.byTooltip('Rotate Mobile screen');
        final phoneMedia = find.byTooltip('Mobile media off');
        final swap = find.byTooltip('Move keyboard to top');
        expect(phoneMedia, findsOneWidget);
        expect(swap, findsOneWidget);
        expect(tester.getSize(rotate), Size.square(compact ? 36 : 28));
        expect(tester.getSize(phoneMedia), Size.square(compact ? 36 : 28));
        expect(tester.getSize(swap), Size.square(compact ? 36 : 28));
        final rotateButton = find.ancestor(
          of: rotate,
          matching: find.byType(IconButton),
        );
        final phoneMediaButton = find.ancestor(
          of: phoneMedia,
          matching: find.byType(IconButton),
        );
        final swapButton = find.ancestor(
          of: swap,
          matching: find.byType(IconButton),
        );
        expect(
          tester.widget<IconButton>(rotateButton).iconSize,
          compact ? 20 : 14,
        );
        expect(
          tester.widget<IconButton>(phoneMediaButton).iconSize,
          compact ? 20 : 14,
        );
        expect(
          tester.widget<IconButton>(swapButton).iconSize,
          compact ? 20 : 14,
        );
        final pad = find.byType(TouchPad);
        if (compact) {
          expect(tester.getCenter(phoneMedia).dx, tester.getCenter(rotate).dx);
          expect(
            tester.getCenter(rotate).dx - tester.getTopLeft(pad).dx,
            lessThan(40),
          );
          expect(
            tester.getTopLeft(phoneMedia).dy,
            greaterThan(tester.getBottomLeft(rotate).dy),
          );
          expect(
            tester.getTopLeft(swap).dy,
            greaterThan(tester.getBottomLeft(phoneMedia).dy),
          );
        } else {
          expect(tester.getCenter(phoneMedia).dy, tester.getCenter(rotate).dy);
          expect(tester.getCenter(swap).dy, tester.getCenter(rotate).dy);
          expect(
            tester.getTopLeft(phoneMedia).dx,
            greaterThan(tester.getTopRight(rotate).dx),
          );
          expect(
            tester.getTopLeft(swap).dx,
            greaterThan(tester.getTopRight(phoneMedia).dx),
          );
          expect(
            tester.getTopLeft(rotate).dy - tester.getTopLeft(pad).dy,
            lessThanOrEqualTo(12),
          );
        }
        expect(
          tester.getBottomLeft(find.byType(TouchPad)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(KeyboardScreen)).dy),
        );
        await tester.tap(swap);
        await tester.pump();
        expect(find.byTooltip('Move trackpad to top'), findsOneWidget);
        expect(
          tester.getBottomLeft(find.byType(KeyboardScreen)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(TouchPad)).dy),
        );
        await tester.tap(find.byTooltip('Move trackpad to top'));
        await tester.pump();
        expect(find.byTooltip('Move keyboard to top'), findsOneWidget);
        expect(
          tester.getBottomLeft(find.byType(TouchPad)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(KeyboardScreen)).dy),
        );
        expect(find.text('Enter'), findsOneWidget);
        expect(find.text('Q'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'mobile mode switch persists and its settings show both controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      tester.view.physicalSize = const Size(1640, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ModesEditor())),
      );
      final mobile = find.ancestor(
        of: find.text('Mobile'),
        matching: find.byType(ListTile),
      );
      expect(mobile, findsOneWidget);
      await tester.tap(
        find.descendant(of: mobile, matching: find.byType(Switch)),
      );
      await tester.pump();
      expect(Settings.instance.mobileTab, isFalse);
      await Settings.instance.load();
      expect(Settings.instance.mobileTab, isFalse);
      expect(
        availableModes(
          mouse: Settings.instance.mouseTab,
          pad: Settings.instance.padTab,
          voice: Settings.instance.voiceTab,
          mobile: Settings.instance.mobileTab,
        ),
        isNot(contains(Mode.mobile)),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SettingsSheet(scope: SettingsScope.mobile)),
        ),
      );
      expect(find.text('Function keys (F1-F12)'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Pointer speed'), 100);
      expect(find.text('Pointer speed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
