import 'package:deskctrl/app_theme.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings are grouped in sections that open on tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsSheet())),
    );
    // The first section is open, the others are closed.
    expect(find.text('Function keys (F1-F12)'), findsOneWidget);
    await tester.tap(find.text('Function keys (F1-F12)'));
    await tester.pumpAndSettle();
    expect(Settings.instance.fnRow, isFalse, reason: 'the switch works');

    await tester.tap(find.text('Keyboard')); // close it again
    await tester.pumpAndSettle();
    for (final t in [
      'Keyboard',
      'Touchpad',
      'Touchpad edges',
      'Tilt mouse',
      'Appearance',
      'Screen brightness',
      'Screens',
      'General',
    ]) {
      await tester.scrollUntilVisible(find.text(t), 100);
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Function keys (F1-F12)'), findsNothing);
    expect(find.text('Pointer speed'), findsNothing);

    await tester.scrollUntilVisible(find.text('Touchpad'), -100);
    await tester.tap(find.text('Touchpad'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pointer speed'), 50);
    expect(find.text('Pointer speed'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Touchpad'), -100);
    await tester.tap(find.text('Touchpad')); // close it
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Touchpad edges'), 100);
    await tester.tap(find.text('Touchpad edges'));
    await tester.pumpAndSettle();
    expect(find.text('Forward / back speed'), findsOneWidget);
    expect(find.text('Top edge slide'), findsOneWidget);
  });

  testWidgets('screen brightness is set per screen and saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsSheet())),
    );
    await tester.tap(find.text('Keyboard')); // close the open section
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Screen brightness'), 100);
    await tester.tap(find.text('Screen brightness'));
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsWidgets, reason: 'screens start on Auto');

    Settings.instance.update(() => Settings.instance.brightPad = 0.4);
    await tester.pump();
    expect(find.text('40%', skipOffstage: false), findsWidgets);
    expect(Settings.instance.brightnessFor('pad'), 0.4);
    expect(Settings.instance.brightnessFor('keyboard'), 0);
    await Settings.instance.load(); // reads what was saved
    expect(Settings.instance.brightPad, 0.4);
    expect(Settings.instance.brightnessFor('mouse'), 0);
  });

  testWidgets('theme and accent colour can be chosen and are saved', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    expect(Settings.instance.theme, 'soft');
    tester.view.physicalSize = const Size(1640, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsSheet())),
    );
    await tester.tap(find.text('Keyboard')); // close the open section
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Appearance'), 100);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full black'));
    await tester.pumpAndSettle();
    expect(Settings.instance.theme, 'amoled');
    await tester.tap(find.text('Black lite'));
    await tester.pumpAndSettle();
    expect(Settings.instance.theme, 'tinted');
    Settings.instance.update(() => Settings.instance.accent = 0xFF39FF88);
    await Settings.instance.load();
    expect(Settings.instance.theme, 'tinted');
    expect(Settings.instance.accent, 0xFF39FF88);
  });

  test('full black is really black, and black lite follows the accent', () {
    expect(AppTheme.colors('amoled', AppTheme.defaultAccent).bg, Colors.black);
    final green = AppTheme.colors('tinted', const Color(0xFF39FF88));
    final blue = AppTheme.colors('tinted', const Color(0xFF4F8CFF));
    expect(green.bg, isNot(blue.bg), reason: 'tint changes with the colour');
    expect(HSLColor.fromColor(green.bg).lightness, lessThan(0.08));
    expect(
      AppTheme.colors('soft', AppTheme.defaultAccent).bg,
      const Color(0xFF14161B),
    );
  });

  testWidgets('each screen shows only its own settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    Future<void> show(SettingsScope scope) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsSheet(scope: scope, onAll: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(SettingsScope.keyboard);
    expect(find.text('Keyboard settings'), findsOneWidget);
    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.text('Touchpad'), findsNothing);
    expect(find.text('Tilt mouse'), findsNothing);
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('General'), findsNothing);
    expect(find.text('All settings'), findsOneWidget);

    await show(SettingsScope.pad);
    expect(find.text('Touchpad settings'), findsOneWidget);
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Touchpad edges'), findsOneWidget);
    expect(find.text('Keyboard'), findsNothing);
    expect(
      find.text('Pointer speed'),
      findsOneWidget,
      reason: 'open by default',
    );

    await show(SettingsScope.mouse);
    expect(find.text('Mouse settings'), findsOneWidget);
    expect(find.text('Tilt mouse'), findsOneWidget);
    expect(find.text('Touchpad'), findsNothing);
    expect(find.text('Tilt speed'), findsOneWidget);

    await show(SettingsScope.all);
    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.text('All settings'),
      findsNothing,
      reason: 'already everything',
    );
    for (final t in [
      'Keyboard',
      'Touchpad',
      'Tilt mouse',
      'Appearance',
      'General',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });
}
