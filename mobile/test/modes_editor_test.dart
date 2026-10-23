import 'package:deskctrl/modes.dart';
import 'package:deskctrl/modes_editor.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ModesEditor())),
      ),
    );
  }

  double y(WidgetTester tester, String label) =>
      tester.getCenter(find.text(label)).dy;

  testWidgets('shows the default order: keyboard, mousepad, mouse', (
    tester,
  ) async {
    await pump(tester);
    expect(y(tester, 'Keyboard'), lessThan(y(tester, 'Mousepad')));
    expect(y(tester, 'Mousepad'), lessThan(y(tester, 'Mouse')));
    expect(find.text('Starts here'), findsOneWidget);
  });

  testWidgets(
    'dragging a handle reorders the list, redraws it, and saves the order',
    (tester) async {
      await pump(tester);
      // Drag Mousepad's handle up above Keyboard.
      final handle = find.byIcon(Icons.drag_handle).at(1);
      await tester.drag(handle, const Offset(0, -140));
      await tester.pumpAndSettle();

      expect(
        Settings.instance.modeOrderList.first,
        Mode.pad,
        reason: 'the order is saved',
      );
      expect(
        y(tester, 'Mousepad'),
        lessThan(y(tester, 'Keyboard')),
        reason: 'and the list redraws',
      );
      // The "Starts here" label follows the first row.
      expect(
        tester.getCenter(find.text('Starts here')).dy,
        closeTo(
          y(tester, 'Mousepad') +
              (tester.getCenter(find.text('Starts here')).dy -
                  y(tester, 'Mousepad')),
          0.1,
        ),
      );
      expect(y(tester, 'Starts here') > y(tester, 'Mousepad') - 1, isTrue);
      expect(
        y(tester, 'Starts here') < y(tester, 'Keyboard'),
        isTrue,
        reason: 'it is under Mousepad now',
      );
    },
  );

  testWidgets(
    'the switches turn Mouse and Mousepad on and off, and the list updates',
    (tester) async {
      await pump(tester);
      final switches = find.byType(Switch);
      expect(
        switches,
        findsNWidgets(3),
        reason: 'Keyboard has no switch, it is always on; Mousepad, Mouse, Voice do',
      );

      await tester.tap(switches.at(1)); // Mouse
      await tester.pump();
      expect(Settings.instance.mouseTab, isFalse);
      expect(
        tester.widget<Switch>(switches.at(1)).value,
        isFalse,
        reason: 'the switch redraws',
      );
      expect(
        availableModes(
          mouse: Settings.instance.mouseTab,
          pad: Settings.instance.padTab,
          order: Settings.instance.modeOrderList,
        ),
        [Mode.keyboard, Mode.pad],
      );

      await tester.tap(switches.at(1));
      await tester.pump();
      expect(Settings.instance.mouseTab, isTrue);
      expect(tester.widget<Switch>(switches.at(1)).value, isTrue);
    },
  );
}
