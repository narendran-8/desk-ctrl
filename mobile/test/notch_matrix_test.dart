import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/edit_menu.dart';
import 'package:deskctrl/keyboard_screen.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/mode_button.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

/// Where the camera hole / notch is on real phones, in dp, in portrait (360 x 800).
const _portrait = Size(360, 800);
final _shapes = <String, Rect>{
  'punch hole, top centre': const Rect.fromLTWH(168, 6, 24, 24),
  'waterdrop notch': const Rect.fromLTWH(140, 0, 80, 26),
  'wide notch': const Rect.fromLTWH(115, 0, 130, 32),
  'very wide notch': const Rect.fromLTWH(80, 0, 200, 30),
  'punch hole, top left': const Rect.fromLTWH(10, 10, 28, 28),
  'punch hole, top right': const Rect.fromLTWH(322, 10, 28, 28),
  'punch hole, low in the corner': const Rect.fromLTWH(12, 40, 26, 26),
};

/// The same hole after turning the phone a quarter turn to the left / right.
Rect _turned(Rect r, bool left) {
  final (w, h) = (_portrait.width, _portrait.height);
  return left
      // top edge -> left edge: (x, y) -> (y, w - x)
      ? Rect.fromLTRB(r.top, w - r.right, r.bottom, w - r.left)
      // top edge -> right edge: (x, y) -> (h - y, x)
      : Rect.fromLTRB(h - r.bottom, r.left, h - r.top, r.right);
}

void main() {
  late FakeAgent agent;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    agent = await FakeAgent.start('tok');
    Settings.instance.saveDevice(
      Device(
        id: 'nm',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await Connection.instance.switchTo('nm');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  tearDown(() async {
    await Connection.instance.disconnectAll();
    await agent.server.close(force: true);
  });

  testWidgets(
    'wherever the camera hole is, no button is under it and none is off the screen',
    (tester) async {
      final problems = <String>[];
      for (final sideBar in [true, false]) {
        Settings.instance.update(() => Settings.instance.sideBar = sideBar);
        for (final MapEntry(key: shape, value: hole) in _shapes.entries) {
          for (final (name, size, rect, padding) in [
            ('portrait', _portrait, hole, EdgeInsets.only(top: hole.bottom)),
            for (final left in [true, false])
              (
                left ? 'landscape, turned left' : 'landscape, turned right',
                const Size(800, 360),
                _turned(hole, left),
                // The system keeps the content off the hole on the side it is on.
                left
                    ? EdgeInsets.only(left: _turned(hole, left).right)
                    : EdgeInsets.only(right: 800 - _turned(hole, left).left),
              ),
          ]) {
            tester.view.devicePixelRatio = 1.0;
            tester.view.physicalSize = size;
            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: size,
                  padding: sideBar ? EdgeInsets.zero : padding,
                  viewPadding: padding,
                  displayFeatures: [
                    DisplayFeature(
                      bounds: rect,
                      type: DisplayFeatureType.cutout,
                      state: DisplayFeatureState.unknown,
                    ),
                  ],
                ),
                child: const MaterialApp(home: Home()),
              ),
            );
            await tester.pumpAndSettle();
            final where =
                '$shape / $name / ${sideBar ? 'notch bar' : 'top bar'}';
            if (tester.takeException() != null)
              problems.add('$where: layout exception');
            final screen = Offset.zero & size;
            final danger = sideBar ? rect.inflate(2) : rect;
            final items = {
              'edit button': find.byType(EditMenuButton),
              'computers': find.byIcon(Icons.computer),
              'connection': find.byIcon(Icons.wifi),
              'mode button': find.byType(ModeButton),
              'settings': find.byIcon(Icons.tune),
            };
            // The screen's own content (the keyboard) starts outside the hole too.
            final content = find.byType(KeyboardScreen);
            if (content.evaluate().isNotEmpty &&
                tester.getRect(content.first).overlaps(rect)) {
              problems.add(
                '$where: the content ${tester.getRect(content.first)} reaches the hole $rect',
              );
            }
            // The icons of one line sit on one line: same centre across the bar.
            final centres = <double>[
              for (final f in items.values)
                if (f.evaluate().isNotEmpty)
                  size.width > size.height
                      ? tester.getCenter(f.first).dx
                      : tester.getCenter(f.first).dy,
            ];
            if (sideBar &&
                hole.height > 0 &&
                centres.isNotEmpty &&
                centres.reduce((a, b) => a > b ? a : b) -
                        centres.reduce((a, b) => a < b ? a : b) >
                    48) {
              problems.add('$where: the icons are not on one line: $centres');
            }
            for (final MapEntry(key: label, value: f) in items.entries) {
              if (f.evaluate().isEmpty) {
                problems.add('$where: $label is missing');
                continue;
              }
              final r = tester.getRect(f.first);
              if (!screen.contains(r.topLeft) ||
                  !screen.contains(r.bottomRight - const Offset(0.5, 0.5))) {
                problems.add('$where: $label is off the screen $r');
              }
              if (r.overlaps(danger))
                problems.add('$where: $label $r is under the hole $rect');
            }
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    },
  );
}
