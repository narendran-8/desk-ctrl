import 'package:deskctrl/connection.dart';
import 'package:deskctrl/custom_key.dart';
import 'package:deskctrl/edit_menu.dart';
import 'package:deskctrl/edit_menu_editor.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  group('the key itself', () {
    test('chord text and initials', () {
      const k = CustomKey(id: 'custom_1', label: 'Reopen', mods: 3, key: 0x17);
      expect(k.chord, 'Ctrl+Shift+T');
      expect(k.modInitials, 'C+S');
      expect(k.modKeys, [0xE0, 0xE1]);
      expect(
        const CustomKey(
          id: 'custom_2',
          label: 'Full',
          mods: 0,
          key: 0x44,
        ).chord,
        'F11',
      );
      expect(
        const CustomKey(
          id: 'custom_3',
          label: 'All',
          mods: 15,
          key: 0x50,
        ).chord,
        'Ctrl+Shift+Alt+Super+Left',
      );
      expect(shortKeyName(0x2A), 'Bksp');
      expect(shortKeyName(0x80E9), 'Vol+');
    });

    test('saved as JSON; unusable entries and repeated ids are dropped', () {
      final keys = [
        const CustomKey(
          id: 'custom_1',
          label: 'Reopen tab',
          mods: 3,
          key: 0x17,
          repeats: true,
        ),
        const CustomKey(id: 'custom_4', label: 'Mute', mods: 0, key: 0x80E2),
      ];
      expect(
        CustomKey.decodeList(CustomKey.encodeList(keys)).map((k) => k.toJson()),
        keys.map((k) => k.toJson()),
      );
      expect(
        CustomKey.decodeList(
          '[{"id":"custom_1","label":"A","mods":1,"key":4},'
          '{"id":"custom_1","label":"again","mods":1,"key":4},'
          '{"id":"x","label":"bad id","mods":1,"key":4},'
          '{"id":"custom_2","label":"","mods":1,"key":4},'
          '{"id":"custom_3","label":"no such key","mods":1,"key":999},'
          '{"id":"custom_5","label":"bad mods","mods":99,"key":4}, 7, null]',
        ).map((k) => k.id),
        ['custom_1'],
      );
      expect(CustomKey.decodeList(''), isEmpty);
      expect(CustomKey.decodeList('not json'), isEmpty);
      expect(CustomKey.decodeList('{"a":1}'), isEmpty);
    });

    test('a long name is cut, the next id is free', () {
      final k = CustomKey.fromJson({
        'id': 'custom_1',
        'label': '  a very long name indeed  ',
        'mods': 0,
        'key': 4,
      })!;
      expect(k.label.length, CustomKey.maxLabel);
      expect(CustomKey.nextId([]), 'custom_1');
      expect(
        CustomKey.nextId([
          const CustomKey(id: 'custom_1', label: 'a', mods: 0, key: 4),
          const CustomKey(id: 'custom_7', label: 'b', mods: 0, key: 4),
        ]),
        'custom_8',
      );
    });

    test('the picker groups hold every key exactly once', () {
      final grouped = [
        for (final g in pickableGroups) ...g.$2.map((k) => k.$2),
      ];
      expect(grouped.length, pickableKeys.length);
      expect(grouped.toSet(), pickableKeys.map((k) => k.$2).toSet());
    });

    test('every pickable key has a name and a code of its own', () {
      expect(pickableKeys.map((k) => k.$1).toSet().length, pickableKeys.length);
      expect(pickableKeys.map((k) => k.$2).toSet().length, pickableKeys.length);
    });
  });

  group('in the menu', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
    });

    test(
      'a custom key is a menu option; a deleted one drops out of the layout',
      () {
        Settings.instance.update(() {
          Settings.instance.editCustom = CustomKey.encodeList(const [
            CustomKey(id: 'custom_1', label: 'Reopen', mods: 3, key: 0x17),
          ]);
        });
        expect(editActionFor('custom_1')!.label, 'Reopen');
        expect(editActionFor('custom_9'), isNull);
        expect(decodeEditLayout('copy,custom_1;custom_9'), [
          ['copy', 'custom_1'],
        ]);
        applyEditLayout('custom_1,copy');
        expect(editRings.first.map((a) => a.id), ['custom_1', 'copy']);
        Settings.instance.update(() => Settings.instance.editCustom = '');
        expect(decodeEditLayout('copy,custom_1'), [
          ['copy'],
        ]);
        applyEditLayout('');
      },
    );

    testWidgets(
      'tapping its wedge presses the chord; a repeating one repeats when held',
      (tester) async {
        tester.view.physicalSize = const Size(1640, 720);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        final agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
        addTearDown(() async {
          await Connection.instance.disconnectAll();
          await agent.server.close(force: true);
        });
        Settings.instance.saveDevice(
          Device(
            id: 'ck',
            name: 'PC',
            host: '127.0.0.1',
            port: agent.port,
            token: 'tok',
          ),
        );
        Settings.instance.update(() {
          Settings.instance.editCustom = CustomKey.encodeList(const [
            CustomKey(id: 'custom_1', label: 'Reopen', mods: 3, key: 0x17),
            CustomKey(
              id: 'custom_2',
              label: 'Down',
              mods: 0,
              key: 0x51,
              repeats: true,
            ),
          ]);
          Settings.instance.editLayout = 'custom_1,custom_2';
        });
        await tester.runAsync(() => Connection.instance.switchTo('ck'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: EditMenuButton(),
              ),
            ),
          ),
        );
        final origin = tester.getCenter(find.byType(EditMenuButton));
        await tester.tap(find.byType(EditMenuButton));
        await tester.pump();
        expect(
          find.text('C+S'),
          findsOneWidget,
          reason: 'the keycap shows the modifiers',
        );
        agent.received.clear();
        await tester.tapAt(EditFan.centreOf(origin, 1, 1, 0, 0));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        expect(agent.received, [
          '1,0,224',
          '1,0,225',
          '1,0,23',
          '2,0,23',
          '2,0,225',
          '2,0,224',
        ], reason: 'Ctrl+Shift+T');

        agent.received.clear();
        final g = await tester.startGesture(
          EditFan.centreOf(origin, 1, 1, 0, 1),
        );
        await tester.pump(const Duration(milliseconds: 900)); // held: repeats
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await g.up();
        await tester.pump();
        expect(
          agent.received.where((m) => m == '1,0,81').length,
          greaterThan(2),
          reason: 'Down repeats',
        );
        await tester.pump(const Duration(seconds: 7));
      },
    );
  });

  group('the editor', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
    });

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: EditMenuEditor())),
        ),
      );
    }

    testWidgets('create from Add, use it in the row, edit it, delete it', (
      tester,
    ) async {
      await pumpEditor(tester);
      List<CustomKey> customs() => customKeys();
      List<List<String>> rows() =>
          decodeEditLayout(Settings.instance.editLayout);

      await tester.tap(find.byKey(const Key('editAdd2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editPickNewCustom')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('customSave')))
            .onPressed,
        isNull,
        reason: 'needs a name and a key',
      );
      await tester.enterText(find.byKey(const Key('customName')), 'Reopen tab');
      await tester.tap(find.byKey(const Key('customMod.Ctrl')));
      await tester.tap(find.byKey(const Key('customMod.Shift')));
      await tester.ensureVisible(find.byKey(const Key('customKey.T')));
      await tester.tap(find.byKey(const Key('customKey.T')));
      await tester.pumpAndSettle();
      expect(find.text('Sends Ctrl+Shift+T'), findsOneWidget);
      await tester.tap(find.byKey(const Key('customSave')));
      await tester.pumpAndSettle();

      expect(customs().single.chord, 'Ctrl+Shift+T');
      expect(customs().single.label, 'Reopen tab');
      expect(rows()[2], [
        'refresh',
        'open_terminal',
        'close_app',
        'custom_1',
      ], reason: 'added to the row');
      expect(
        find.text('Ctrl+Shift+T'),
        findsOneWidget,
        reason: 'listed under Custom keys',
      );

      // Edit: new name and repeat.
      await tester.tap(find.byKey(const Key('customEdit.custom_1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('customName')), 'Tab back');
      await tester.tap(find.byKey(const Key('customRepeat')));
      await tester.tap(find.byKey(const Key('customSave')));
      await tester.pumpAndSettle();
      expect(customs().single.label, 'Tab back');
      expect(customs().single.repeats, isTrue);
      expect(
        customs().single.id,
        'custom_1',
        reason: 'same id, so the row keeps it',
      );

      // Delete: gone from the list and the row.
      await tester.tap(find.byKey(const Key('customDelete.custom_1')));
      await tester.pumpAndSettle();
      expect(customs(), isEmpty);
      expect(rows()[2], ['refresh', 'open_terminal', 'close_app']);
    });

    testWidgets(
      'a custom key can also be made in the Custom keys list and added later',
      (tester) async {
        await pumpEditor(tester);
        await tester.tap(find.byKey(const Key('customNew')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('customName')), 'Full');
        await tester.ensureVisible(find.byKey(const Key('customKey.F11')));
        await tester.tap(find.byKey(const Key('customKey.F11')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('customSave')));
        await tester.pumpAndSettle();
        expect(customKeys().single.chord, 'F11');
        expect(
          decodeEditLayout(Settings.instance.editLayout),
          defaultEditLayout,
          reason: 'not in a row yet',
        );

        await tester.tap(find.byKey(const Key('editAdd0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('editPick.custom_1')));
        await tester.pumpAndSettle();
        expect(
          decodeEditLayout(Settings.instance.editLayout)[0].last,
          'custom_1',
        );
      },
    );
  });
}
