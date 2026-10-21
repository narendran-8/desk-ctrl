import 'package:deskctrl/edit_menu.dart';
import 'package:deskctrl/edit_menu_editor.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
  });

  test('layout text: round trip, unknown ids dropped, limits, default', () {
    expect(decodeEditLayout(''), defaultEditLayout);
    expect(decodeEditLayout('nope;;'), defaultEditLayout);
    expect(decodeEditLayout('copy,xx,paste;;enter'), [
      ['copy', 'paste'],
      ['enter'],
    ]);
    expect(
      decodeEditLayout('copy,cut,paste,undo,redo,find,save;a;b;c;enter')[0],
      hasLength(maxEditPerRow),
    );
    expect(
      decodeEditLayout('copy;cut;paste;undo;redo'),
      hasLength(maxEditRows),
    );
    final rows = [
      ['find', 'save'],
      ['tab'],
    ];
    expect(decodeEditLayout(encodeEditLayout(rows)), rows);
    for (final r in defaultEditLayout) {
      expect(r.every(editCatalog.containsKey), isTrue);
    }
  });

  test('applyEditLayout changes the rings', () {
    applyEditLayout('find,save;tab');
    expect(editRings.map((r) => r.map((a) => a.id)), [
      ['find', 'save'],
      ['tab'],
    ]);
    applyEditLayout('');
    expect(editRings.length, 3);
  });

  test('the options of a row share the whole quarter', () {
    for (final n in [1, 2, 3, 4, 5, 6]) {
      applyEditLayout(
        ['copy', 'cut', 'paste', 'undo', 'redo', 'find'].take(n).join(','),
      );
      expect(EditFan.sweep(0) * n, closeTo(1.5707963, 1e-6));
    }
    applyEditLayout('');
  });

  testWidgets('the editor adds, moves and removes options and rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: EditMenuEditor())),
      ),
    );
    List<List<String>> rows() => decodeEditLayout(Settings.instance.editLayout);
    expect(rows(), defaultEditLayout);

    // add an option to the last row
    await tester.tap(find.byKey(const Key('editAdd2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editPick.find')));
    await tester.pumpAndSettle();
    expect(rows()[2], ['refresh', 'open_terminal', 'close_app', 'find']);

    // move it earlier
    await tester.tap(find.byKey(const Key('editOption2.3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move earlier'));
    await tester.pumpAndSettle();
    expect(rows()[2], ['refresh', 'open_terminal', 'find', 'close_app']);

    // remove an option
    await tester.tap(find.byKey(const Key('editOption0.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(rows()[0], ['cut', 'paste', 'undo', 'select_all']);

    // row up, row delete
    await tester.tap(find.byKey(const Key('editRowUp2')));
    await tester.pumpAndSettle();
    expect(rows()[1], ['refresh', 'open_terminal', 'find', 'close_app']);
    await tester.tap(find.byKey(const Key('editRowDelete1')));
    await tester.pumpAndSettle();
    expect(rows().length, 2);

    // a fourth row cannot be added to three; reset restores the standard options
    await tester.tap(find.byKey(const Key('editReset')));
    await tester.pumpAndSettle();
    expect(rows(), defaultEditLayout);
    expect(find.byKey(const Key('editAddRow')), findsNothing);
  });
}
