import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/mode_button.dart';
import 'package:deskctrl/modes.dart';
import 'package:deskctrl/mobile_screen.dart';
import 'package:deskctrl/mouse_screen.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const all = [Mode.keyboard, Mode.pad, Mode.mouse];

  Future<List<Mode>> pumpButton(
    WidgetTester tester, {
    Mode mode = Mode.keyboard,
    Mode? previous,
    List<Mode> modes = all,
  }) async {
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final picked = <Mode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ModeButton(
              mode: mode,
              modes: modes,
              previous: previous,
              onMode: picked.add,
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  Future<void> tap(WidgetTester tester) async {
    await tester.tap(find.byType(ModeButton));
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets(
    'one tap goes back to the mode before; with none yet, to the next',
    (tester) async {
      var picked = await pumpButton(
        tester,
        mode: Mode.mouse,
        previous: Mode.keyboard,
      );
      await tap(tester);
      expect(
        picked,
        isEmpty,
        reason: 'it waits to see whether a second tap follows',
      );
      await tester.pump(modeDoubleTapWindow);
      expect(picked, [Mode.keyboard]);

      picked = await pumpButton(tester, mode: Mode.keyboard);
      await tap(tester);
      await tester.pump(modeDoubleTapWindow);
      expect(picked, [Mode.pad], reason: 'no previous mode yet: the next one');

      picked = await pumpButton(tester, mode: Mode.pad, previous: Mode.pad);
      await tap(tester);
      await tester.pump(modeDoubleTapWindow);
      expect(picked, [
        Mode.mouse,
      ], reason: 'a previous mode that is the current one is no use');

      picked = await pumpButton(tester, mode: Mode.pad, previous: Mode.voice);
      await tap(tester);
      await tester.pump(modeDoubleTapWindow);
      expect(picked, [
        Mode.mouse,
      ], reason: 'a previous mode that is switched off is skipped');
    },
  );

  testWidgets('a double tap goes to the next mode in the order', (
    tester,
  ) async {
    final picked = await pumpButton(
      tester,
      mode: Mode.keyboard,
      previous: Mode.mouse,
    );
    await tap(tester);
    await tap(tester);
    await tester.pump(modeDoubleTapWindow * 2);
    expect(picked, [
      Mode.pad,
    ], reason: 'one switch, to the next mode, not to the previous one');
  });

  testWidgets('a double tap wraps around the order', (tester) async {
    final picked = await pumpButton(
      tester,
      mode: Mode.mouse,
      previous: Mode.pad,
    );
    await tap(tester);
    await tap(tester);
    await tester.pump(modeDoubleTapWindow * 2);
    expect(picked, [Mode.keyboard]);
  });

  testWidgets('two taps far apart are two single taps', (tester) async {
    final picked = await pumpButton(
      tester,
      mode: Mode.keyboard,
      previous: Mode.pad,
    );
    await tap(tester);
    await tester.pump(modeDoubleTapWindow * 2);
    await tap(tester);
    await tester.pump(modeDoubleTapWindow * 2);
    expect(picked, [
      Mode.pad,
      Mode.pad,
    ], reason: 'previous both times (the test does not move on)');
  });

  testWidgets('a single mode: taps do nothing', (tester) async {
    final picked = await pumpButton(tester, modes: const [Mode.keyboard]);
    await tap(tester);
    await tester.pump(modeDoubleTapWindow * 2);
    expect(picked, isEmpty);
  });

  testWidgets(
    'in the app: tap goes back and forth, double tap goes round the modes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      Settings.instance.update(() => Settings.instance.voiceTab = true);
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Home()));
      await tester.pump();

      Future<void> single() async {
        await tester.tap(find.byType(ModeButton));
        await tester.pump(
          modeDoubleTapWindow + const Duration(milliseconds: 50),
        );
        await tester.pump();
      }

      Future<void> double() async {
        await tester.tap(find.byType(ModeButton));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(find.byType(ModeButton));
        await tester.pump(
          modeDoubleTapWindow + const Duration(milliseconds: 50),
        );
        await tester.pump();
      }

      expect(find.byType(KeyboardScreen), findsOneWidget);
      await single(); // no previous mode yet: the next one
      expect(find.byType(MouseScreen), findsOneWidget);
      await single(); // back
      expect(find.byType(KeyboardScreen), findsOneWidget);
      await single(); // and forth
      expect(find.byType(MouseScreen), findsOneWidget);

      await double(); // mouse -> trackpad
      expect(find.byType(PadScreen), findsOneWidget);
      await double(); // trackpad -> voice
      expect(find.byType(VoiceScreen), findsOneWidget);
      await double(); // voice -> mobile
      expect(find.byType(MobileScreen), findsOneWidget);
      await double(); // mobile -> keyboard (wraps)
      expect(find.byType(KeyboardScreen), findsOneWidget);
      await single(); // back to where the last double tap came from
      expect(find.byType(MobileScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
