import 'package:deskctrl/mode_button.dart';
import 'package:deskctrl/modes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<Mode>> pump(
    WidgetTester tester, {
    Mode mode = Mode.keyboard,
    MenuSide side = MenuSide.right,
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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ModeButton(
                mode: mode,
                modes: const [Mode.keyboard, Mode.pad, Mode.mouse],
                onMode: picked.add,
                side: side,
              ),
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('a tap on the keyboard button switches to the trackpad', (
    tester,
  ) async {
    final picked = await pump(tester);
    await tester.tap(find.byType(ModeButton));
    await tester.pump(const Duration(milliseconds: 600));
    expect(picked, [Mode.pad]);
    expect(
      find.text('Mouse'),
      findsNothing,
      reason: 'no menu after a plain tap',
    );
  });

  testWidgets(
    'long-press opens a menu with the other modes; drag onto one and let go to pick it',
    (tester) async {
      final picked = await pump(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(ModeButton)),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Mousepad'),
        findsOneWidget,
        reason: 'the others are listed',
      );
      expect(
        find.ancestor(
          of: find.text('Mousepad'),
          matching: find.byType(Material),
        ),
        findsWidgets,
        reason:
            'without a Material the menu text is drawn with a yellow underline',
      );
      expect(find.text('Mouse'), findsOneWidget);
      expect(
        find.text('Keyboard'),
        findsNothing,
        reason: 'the current mode is not offered',
      );

      // The trackpad comes first, then the mouse (the order from Settings).
      expect(
        tester.getCenter(find.text('Mousepad')).dy,
        lessThan(tester.getCenter(find.text('Mouse')).dy),
      );

      await g.moveTo(tester.getCenter(find.text('Mouse')));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(picked, [Mode.mouse]);
      expect(find.text('Mousepad'), findsNothing, reason: 'the menu closes');
    },
  );

  testWidgets('letting go away from the menu picks nothing', (tester) async {
    final picked = await pump(tester);
    final g = await tester.startGesture(
      tester.getCenter(find.byType(ModeButton)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Mouse'), findsOneWidget);
    await g.moveTo(const Offset(700, 300)); // nowhere near the menu
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(
      picked,
      isEmpty,
      reason: 'a long-press alone neither switches nor cycles',
    );
    expect(find.text('Mouse'), findsNothing);
  });

  testWidgets('a drag that starts before the long-press time is not a tap', (
    tester,
  ) async {
    final picked = await pump(tester);
    final g = await tester.startGesture(
      tester.getCenter(find.byType(ModeButton)),
    );
    await g.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    await tester.pump();
    expect(picked, isEmpty);
    expect(
      find.text('Mouse'),
      findsNothing,
      reason: 'moving cancels the long-press',
    );
  });

  testWidgets('the menu lists whatever is not current, in order', (
    tester,
  ) async {
    await pump(tester, mode: Mode.pad);
    final g = await tester.startGesture(
      tester.getCenter(find.byType(ModeButton)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.text('Mouse'), findsOneWidget);
    expect(find.text('Mousepad'), findsNothing);
    await g.up();
    await tester.pump();
  });
}
