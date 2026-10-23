import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/phone_media.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Mobile button routes edge media actions to the phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(PhoneMedia.channel, (call) async {
      calls.add('${call.method}:${call.arguments}');
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(PhoneMedia.channel, null),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PadScreen())),
    );
    expect(find.byTooltip('Mobile media off'), findsOneWidget);
    await tester.tap(find.byTooltip('Mobile media off'));
    await tester.pump();
    expect(find.byTooltip('Mobile media on'), findsOneWidget);
    final rect = tester.getRect(find.byType(TouchPad));
    final g = await tester.startGesture(rect.topLeft + const Offset(12, 200));
    await g.moveBy(const Offset(0, -48));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(calls, contains('volume:1'));

    Settings.instance.update(
      () => Settings.instance.padPhoneMediaButton = false,
    );
    await tester.pump();
    expect(find.byIcon(Icons.smartphone), findsNothing);
    expect(tester.widget<TouchPad>(find.byType(TouchPad)).phoneMedia, isFalse);
  });
}
