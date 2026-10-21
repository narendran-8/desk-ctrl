import 'package:deskctrl/settings.dart';
import 'package:deskctrl/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final (w, h) in [(1640.0, 720.0), (720.0, 1640.0)]) {
    testWidgets(
      'the Screens section opens without errors in ${w.toInt()}x${h.toInt()}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await Settings.instance.load();
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => openSettings(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keyboard')); // close the open section
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Screens'), 100);
        await tester.ensureVisible(find.text('Screens'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Screens'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'opening Screens');
        expect(find.text('Modes', skipOffstage: false), findsOneWidget);

        // The list ends where it should: scrolling down reaches the last setting and stops.
        final list = find.byType(Scrollable).first;
        await tester.drag(list, Offset(0, -h), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.drag(list, Offset(0, -h), warnIfMissed: false);
        await tester.pumpAndSettle();
        final pos = tester.state<ScrollableState>(list).position;
        expect(pos.pixels, pos.maxScrollExtent, reason: 'it ends');
        expect(pos.maxScrollExtent, lessThan(5000), reason: 'a finite list');
        expect(
          find.text('General'),
          findsOneWidget,
          reason: 'the last section is reachable',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
