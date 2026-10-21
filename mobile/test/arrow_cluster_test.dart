import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('arrow keys: Left and Right full height, Up stacked over Down, no empty cells', () {
    for (final functionRow in [true, false]) {
      for (final showFn in [true, false]) {
        for (final join in [true, false]) {
          final rows = layoutFor(
            functionRow: functionRow,
            joinDelete: join,
            showFn: showFn,
          );
          final all = rows.expand((r) => r).toList();
          final where = 'row=$functionRow fn=$showFn join=$join';

          // Nothing is left empty: every cell is a real key or a stacked pair of keys.
          expect(
            all.every((k) => k.stack != null || k.hid >= 0),
            isTrue,
            reason: where,
          );

          // The bottom row ends with Left, [Up over Down], Right.
          final bottom = rows.last;
          final tail = bottom.sublist(bottom.length - 3);
          expect(tail[0].label, '←', reason: where);
          expect(tail[1].stack!.map((k) => k.label).toList(), [
            '↑',
            '↓',
          ], reason: where);
          expect(tail[2].label, '→', reason: where);

          // Each arrow exists once, and Up is no longer in the Shift row.
          final labels = [
            for (final k in all) ...(k.stack?.map((h) => h.label) ?? [k.label]),
          ];
          for (final a in ['←', '↑', '↓', '→']) {
            expect(
              labels.where((l) => l == a),
              hasLength(1),
              reason: '$a $where',
            );
          }

          // The Shift row is back to normal, and the bottom row is as wide as the rest.
          final shiftRow = rows[rows.length - 2];
          expect(
            shiftRow
                .where((k) => k.label == 'Shift')
                .map((k) => k.flex)
                .toList(),
            [2.3, 2.7],
            reason: where,
          );
          double total(List<KeyDef> row) => row.fold(0.0, (s, k) => s + k.flex);
          expect(total(shiftRow), closeTo(15, 1e-9), reason: where);
          expect(total(bottom), closeTo(15, 1e-9), reason: 'bottom row $where');
        }
      }
    }
  });

  testWidgets(
    'on screen: no gaps, every row spans the full width, Up is right above Down',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: KeyboardScreen())),
      );

      Rect key(String label, {int index = 0}) {
        final f = find.byWidgetPredicate(
          (w) => w is KeyButton && w.def.label == label,
        );
        return tester.getRect(f.at(index));
      }

      final up = key('↑'),
          down = key('↓'),
          left = key('←'),
          right = key('→'),
          ctrl = key('Ctrl');

      // Up is directly above Down: same column, touching, and together exactly as tall as the row.
      expect(up.left, closeTo(down.left, 0.5));
      expect(up.width, closeTo(down.width, 0.5));
      expect(
        up.bottom,
        closeTo(down.top, 4.1),
        reason: 'only the normal key margin between them',
      );
      expect(
        up.top,
        closeTo(ctrl.top, 0.5),
        reason: 'Up reaches the top of the row',
      );
      expect(
        down.bottom,
        closeTo(ctrl.bottom, 0.5),
        reason: 'Down reaches the bottom of the row',
      );

      // Left and Right are full height and sit either side, with no gap between the three columns.
      expect(left.height, closeTo(ctrl.height, 0.5));
      expect(right.height, closeTo(ctrl.height, 0.5));
      expect(left.right, closeTo(up.left, 0.5));
      expect(up.right, closeTo(right.left, 0.5));

      // Every row starts and ends at the same edges: no ragged gap at either end.
      final firsts = [
        key('Esc'),
        key('Tab'),
        key('Caps'),
        key('Shift'),
        key('Ctrl'),
      ];
      final lasts = [
        key('Backspace'),
        key('\\'),
        key('Enter'),
        key('Shift', index: 1),
        right,
      ];
      for (final r in firsts) {
        expect(
          r.left,
          closeTo(firsts.first.left, 0.5),
          reason: 'left edges line up',
        );
      }
      for (final r in lasts) {
        expect(
          r.right,
          closeTo(lasts.first.right, 0.5),
          reason: 'right edges line up',
        );
      }
    },
  );
}
