import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  fnTests();
  functionRowTests();
  testWidgets('holding Shift lights up the shifted symbols', (tester) async {
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KeyboardScreen())),
    );

    TextStyle style(String symbol) =>
        tester.widget<Text>(find.text(symbol)).style!;
    // Every key that has a second symbol.
    const symbols = [
      '!',
      '@',
      '#',
      r'$',
      '%',
      '^',
      '&',
      '*',
      '(',
      ')',
      '_',
      '+',
      '{',
      '}',
      '|',
      ':',
      '"',
      '<',
      '>',
      '?',
      '~',
    ];

    for (final s in symbols) {
      expect(
        style(s).fontSize,
        11,
        reason: '$s is small and dim while Shift is up',
      );
    }

    final shift = await tester.startGesture(
      tester.getCenter(find.text('Shift').first),
    );
    await tester.pump();
    for (final s in symbols) {
      expect(style(s).fontSize, 19, reason: '$s is large while Shift is held');
      expect(
        style(s).color,
        const Color(0xFFFFD166),
        reason: '$s is highlighted',
      );
    }

    await shift.up();
    await tester.pump();
    for (final s in symbols) {
      expect(
        style(s).fontSize,
        11,
        reason: '$s goes back when Shift is released',
      );
    }
  });

  testWidgets(
    'either Shift key works, and both must be released to turn it off',
    (tester) async {
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: KeyboardScreen())),
      );
      double size() => tester.widget<Text>(find.text('?')).style!.fontSize!;

      final left = await tester.startGesture(
        tester.getCenter(find.text('Shift').first),
      );
      final right = await tester.startGesture(
        tester.getCenter(find.text('Shift').last),
      );
      await tester.pump();
      expect(size(), 19);
      await left.up();
      await tester.pump();
      expect(size(), 19, reason: 'the right Shift is still down');
      await right.up();
      await tester.pump();
      expect(size(), 11);
    },
  );
}

// ---- Fn key on/off ----
void fnTests() {
  testWidgets('the Fn key can be switched off in Settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KeyboardScreen())),
    );

    expect(find.text('Fn'), findsOneWidget, reason: 'on by default');

    // Turn the Fn layer on: F1 becomes "Dim".
    await tester.tap(find.text('Fn'));
    await tester.pump();
    expect(find.text('Dim'), findsOneWidget);
    expect(find.text('F1'), findsNothing);

    // Switch Fn off in Settings: the key goes and the F-row is plain again.
    Settings.instance.update(() => Settings.instance.fnKey = false);
    await tester.pump();
    expect(find.text('Fn'), findsNothing);
    expect(find.text('Dim'), findsNothing);
    expect(find.text('F1'), findsOneWidget);

    // Back on: the key returns, and the layer starts off.
    Settings.instance.update(() => Settings.instance.fnKey = true);
    await tester.pump();
    expect(find.text('Fn'), findsOneWidget);
  });
}

void functionRowTests() {
  testWidgets('the function row can be hidden, keeping Esc and Del', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KeyboardScreen())),
    );

    final rowsBefore = find.byType(Row).evaluate().length;
    expect(find.text('F1'), findsOneWidget);
    expect(find.text('F12'), findsOneWidget);
    expect(find.text('Fn'), findsOneWidget);
    final qTopBefore = tester.getTopLeft(find.text('Q')).dy;

    Settings.instance.update(() => Settings.instance.fnRow = false);
    await tester.pump();
    for (var i = 1; i <= 12; i++) {
      expect(find.text('F$i'), findsNothing, reason: 'F$i is hidden');
    }
    expect(
      find.text('Fn'),
      findsNothing,
      reason: 'Fn has nothing to switch without the F-row',
    );
    expect(find.text('Esc'), findsOneWidget, reason: 'Esc is kept');
    expect(find.text('Del'), findsOneWidget, reason: 'Del is kept');
    expect(
      find.byType(Row).evaluate().length,
      lessThan(rowsBefore),
      reason: 'one row fewer',
    );
    expect(
      tester.getTopLeft(find.text('Q')).dy,
      lessThan(qTopBefore),
      reason: 'keys move up, the rest gets taller',
    );

    // Esc now sits at the start of the number row, to the left of the ` key.
    expect(
      tester.getTopLeft(find.text('Esc')).dx,
      lessThan(tester.getTopLeft(find.text('`')).dx),
    );

    Settings.instance.update(() => Settings.instance.fnRow = true);
    await tester.pump();
    expect(find.text('F1'), findsOneWidget);
    expect(find.text('Fn'), findsOneWidget);
  });
}
