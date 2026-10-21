import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:deskctrl/main.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, {Rect? notch}) async {
    const size = Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          displayFeatures: [
            if (notch != null)
              DisplayFeature(
                bounds: notch,
                type: DisplayFeatureType.cutout,
                state: DisplayFeatureState.unknown,
              ),
          ],
        ),
        child: const MaterialApp(home: Home()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The top bar names the screen next to its icon on a wide phone; the bar around the notch is icons only.
  final topBar = find.text('Keyboard');
  const notch = Rect.fromLTWH(0, 150, 30, 60);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
  });

  testWidgets(
    'auto (the default): a phone with a notch gets the bar around it, one without gets the top bar',
    (tester) async {
      expect(Settings.instance.notchBar, 'auto');
      await pumpHome(tester, notch: notch);
      expect(topBar, findsNothing, reason: 'icons beside the notch');
      await pumpHome(tester);
      expect(topBar, findsOneWidget, reason: 'no notch: the ordinary top bar');
    },
  );

  testWidgets('"on" always uses the bar around the notch, "off" never does', (
    tester,
  ) async {
    Settings.instance.update(() => Settings.instance.notchBar = 'on');
    await pumpHome(tester);
    expect(topBar, findsNothing);
    Settings.instance.update(() => Settings.instance.notchBar = 'off');
    await pumpHome(tester, notch: notch);
    expect(topBar, findsOneWidget);
  });

  test('saved settings: the old on / off switch becomes on / auto', () async {
    for (final (prefs, want) in [
      (<String, Object>{}, 'auto'),
      (<String, Object>{'sideBar': true}, 'on'),
      (<String, Object>{'sideBar': false}, 'auto'),
      (<String, Object>{'notchBar': 'off'}, 'off'),
      (<String, Object>{'notchBar': 'nonsense'}, 'auto'),
    ]) {
      SharedPreferences.setMockInitialValues(prefs);
      await Settings.instance.load();
      expect(Settings.instance.notchBar, want, reason: '$prefs');
    }
    expect(Settings.instance.useNotchBar(hasNotch: true), isTrue);
  });
}
