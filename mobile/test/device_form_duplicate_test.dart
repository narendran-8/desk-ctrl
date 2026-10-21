import 'package:deskctrl/connection.dart';
import 'package:deskctrl/device_form.dart';
import 'package:deskctrl/settings.dart';
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
    'adding a computer that is already in the list updates it instead of adding it again',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
      Settings.instance.saveDevice(
        Device(
          id: 'desk',
          name: 'Desk',
          host: '127.0.0.1',
          port: agent!.port,
          token: 'old',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DeviceFormScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      // The same computer typed in again (this time with the current token).
      await tester.enterText(
        field('Desktop IP (127.0.0.1 for USB)'),
        '127.0.0.1',
      );
      await tester.enterText(field('Port'), '${agent!.port}');
      await tester.enterText(
        field('Pairing token (shown by the agent)'),
        'tok',
      );
      await tester.tap(find.text('Save & connect'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump(
        const Duration(milliseconds: 600),
      ); // the note is still showing

      expect(
        Settings.instance.devices.length,
        1,
        reason: 'not added a second time',
      );
      final d = Settings.instance.devices.single;
      expect(
        (d.id, d.name, d.token),
        ('desk', 'Desk', 'tok'),
        reason: 'the entry was updated',
      );
      expect(find.textContaining('already in your list'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
}
