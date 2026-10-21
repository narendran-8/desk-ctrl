import 'package:deskctrl/connection.dart';
import 'package:deskctrl/edit_menu.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/settings.dart';

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  FakeAgent? agent;

  tearDown(() async {
    await Connection.instance.disconnectAll();
    await agent?.server.close(force: true);
    agent = null;
  });

  testWidgets(
    'the whole app, with the edit button, lays out in every orientation and bar style',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 2.0;
      agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
      Settings.instance.saveDevice(
        Device(
          id: 'rot',
          name: 'PC',
          host: '127.0.0.1',
          port: agent!.port,
          token: 'tok',
        ),
      );
      await tester.runAsync(() => Connection.instance.switchTo('rot'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );

      for (final sideBar in [true, false]) {
        Settings.instance.update(() => Settings.instance.sideBar = sideBar);
        for (final (w, h, name) in [
          (1640.0, 720.0, 'landscape'),
          (720.0, 1640.0, 'portrait'),
          (1920.0, 1080.0, 'tablet landscape'),
        ]) {
          tester.view.physicalSize = Size(w, h);
          await tester.pumpWidget(const MaterialApp(home: Home()));
          await tester.pumpAndSettle();
          final where = '$name, notch bar ${sideBar ? 'on' : 'off'}';
          expect(tester.takeException(), isNull, reason: 'no overflow: $where');
          expect(find.byType(EditMenuButton), findsOneWidget, reason: where);
          final c = tester.getCenter(find.byType(EditMenuButton));
          expect(
            c.dx < 130 && c.dy < 130,
            isTrue,
            reason: 'in the top-left corner: $where at $c',
          );

          await tester.tap(find.byType(EditMenuButton));
          await tester.pumpAndSettle();
          expect(find.byType(EditFan), findsOneWidget, reason: where);
          expect(tester.takeException(), isNull, reason: where);
          await tester.tapAt(
            const Offset(10, 10),
          ); // outside the ring (inside the button's hole)
          await tester.pumpAndSettle();
          expect(find.byType(EditFan), findsNothing, reason: where);
        }
      }
    },
  );

  testWidgets(
    'with the camera on the right (phone turned the other way round) the rail and the fan are on the right',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(1640, 720);
      agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
      Settings.instance.saveDevice(
        Device(
          id: 'rot2',
          name: 'PC',
          host: '127.0.0.1',
          port: agent!.port,
          token: 'tok',
        ),
      );
      await tester.runAsync(() => Connection.instance.switchTo('rot2'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      Settings.instance.update(() => Settings.instance.sideBar = true);

      final cutout = DisplayFeature(
        bounds: const Rect.fromLTWH(
          790,
          140,
          30,
          80,
        ), // logical px: on the right edge of 820 x 360
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(820, 360),
            displayFeatures: [cutout],
          ),
          child: const MaterialApp(home: Home()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final c = tester.getCenter(find.byType(EditMenuButton));
      expect(
        c.dx > 700 && c.dy < 130,
        isTrue,
        reason: 'the button is in the top-right corner now: $c',
      );

      await tester.tap(find.byType(EditMenuButton));
      await tester.pumpAndSettle();
      final fan = tester.widget<EditFan>(find.byType(EditFan));
      expect(
        (fan.sx, fan.sy),
        (-1, 1),
        reason: 'opens towards the left and down',
      );
      for (var ring = 0; ring < editRings.length; ring++) {
        for (var w = 0; w < editRings[ring].length; w++) {
          final p = EditFan.centreOf(fan.origin, fan.sx, fan.sy, ring, w);
          expect(
            p.dx > 0 && p.dx < 820 && p.dy > 0 && p.dy < 360,
            isTrue,
            reason: 'ring $ring wedge $w on screen: $p',
          );
        }
      }
    },
  );
}
