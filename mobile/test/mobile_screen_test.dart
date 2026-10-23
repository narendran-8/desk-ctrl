import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/mobile_screen.dart';
import 'package:deskctrl/modes.dart';
import 'package:deskctrl/modes_editor.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mobile screen fits a landscape phone with pad above keys', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MobileScreen())),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(TouchPad), findsOneWidget);
    expect(find.byType(KeyboardScreen), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(TouchPad)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(KeyboardScreen)).dy),
    );
    expect(find.text('Enter'), findsOneWidget);
  });

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
