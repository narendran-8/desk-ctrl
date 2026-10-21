import 'dart:convert';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/devices_screen.dart';
import 'package:deskctrl/edit_menu.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('offline the whole app is there; the strip opens the computers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Home()));
    await tester.pump();

    expect(find.byType(EditMenuButton), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget, reason: 'settings');
    expect(find.text('Offline - tap to add a computer'), findsOneWidget);

    await tester.tap(find.text('Offline - tap to add a computer'));
    await tester.pumpAndSettle();
    expect(find.byType(DevicesSheet), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets(
    'a remembered computer that is not there yet: "Looking for ..." in the strip',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'devices': jsonEncode([
          Device(
            id: 'pc',
            name: 'Desk PC',
            host: '127.0.0.1',
            port: 1,
            token: 't',
          ).toJson(),
        ]),
        'lastConnected': ['pc'],
      });
      await Settings.instance.load();
      Session.waitInterval = const Duration(seconds: 30);
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => Connection.instance.restoreLast());
      await tester.pumpWidget(const MaterialApp(home: Home()));
      await tester.pump();
      expect(find.textContaining('Looking for Desk PC'), findsOneWidget);
      await tester.runAsync(() => Connection.instance.disconnectAll());
      await tester.pumpWidget(const SizedBox());
    },
  );
}
