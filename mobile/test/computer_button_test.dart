import 'package:deskctrl/connection.dart';
import 'package:deskctrl/device_color.dart';
import 'package:deskctrl/devices_screen.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  testWidgets(
    'computer button toggles, cycles, and opens the connection sheet',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final agents = <FakeAgent>[];
      for (final id in ['a', 'b', 'c']) {
        final agent = (await tester.runAsync(() => FakeAgent.start(id)))!;
        agents.add(agent);
        Settings.instance.saveDevice(
          Device(
            id: id,
            name: 'Computer $id',
            host: '127.0.0.1',
            port: agent.port,
            token: id,
          ),
        );
      }
      final c = Connection.instance;
      addTearDown(() async {
        await c.disconnectAll();
        for (final agent in agents) {
          await agent.server.close(force: true);
        }
      });
      await tester.runAsync(c.connectAll);
      await tester.runAsync(() => c.switchTo('b'));
      await tester.pumpWidget(const MaterialApp(home: Home()));
      final button = find.ancestor(
        of: find.byIcon(Icons.computer),
        matching: find.byType(InkWell),
      );
      expect(button, findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.computer)).color,
        deviceColor('b'),
      );
      expect(find.byIcon(Icons.link), findsOneWidget);
      expect(deviceColor('a'), isNot(deviceColor('b')));
      expect(deviceColor('b'), isNot(deviceColor('c')));

      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 350));
      expect(c.activeId, 'a');
      expect(
        tester.widget<Icon>(find.byIcon(Icons.computer)).color,
        deviceColor('a'),
      );
      expect(
        find.byIcon(Icons.link),
        findsOneWidget,
        reason: 'the connection control is stable while switching computers',
      );
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        c.activeId,
        'b',
        reason: 'single taps alternate with the previous',
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.computer)).color,
        deviceColor('b'),
      );
      expect(find.byIcon(Icons.link), findsOneWidget);

      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 350));
      expect(c.activeId, 'c', reason: 'double tap advances in saved order');
      expect(
        tester.widget<Icon>(find.byIcon(Icons.computer)).color,
        deviceColor('c'),
      );
      expect(find.byIcon(Icons.link), findsOneWidget);

      await tester.runAsync(() => c.disconnectDevice('a'));
      await tester.pump();
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 350));
      expect(c.activeId, 'b', reason: 'offline computers are skipped');

      await tester.longPress(button);
      await tester.pumpAndSettle();
      expect(find.byType(DevicesSheet), findsOneWidget);
      expect(c.activeId, 'b', reason: 'long press only opens settings');
    },
  );

  testWidgets('USB/Wi-Fi and Bluetooth computers share a stable link button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final wifi = (await tester.runAsync(() => FakeAgent.start('wifi-token')))!;
    final bt = FakeBt('bt-token')..install();
    final c = Connection.instance;
    addTearDown(() async {
      await c.disconnectAll();
      bt.uninstall();
      await wifi.server.close(force: true);
    });
    Settings.instance
      ..saveDevice(
        Device(
          id: 'wifi-computer',
          name: 'Wi-Fi computer',
          host: '127.0.0.1',
          port: wifi.port,
          token: 'wifi-token',
        ),
      )
      ..saveDevice(
        Device(
          id: 'bt-computer',
          name: 'Bluetooth computer',
          token: 'bt-token',
          useWifi: false,
          useBt: true,
          btAddress: 'AA:BB:CC:DD:EE:FF',
        ),
      );
    await tester.runAsync(c.connectAll);
    await tester.runAsync(() => c.switchTo('wifi-computer'));
    await tester.pumpWidget(const MaterialApp(home: Home()));
    expect(c.activeCount, 2);
    expect(c.active!.effective!.transport, Transport.wifi);
    expect(find.byIcon(Icons.link), findsOneWidget);

    final computerButton = find.ancestor(
      of: find.byIcon(Icons.computer),
      matching: find.byType(InkWell),
    );
    await tester.tap(computerButton);
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.activeId, 'bt-computer');
    expect(c.active!.effective!.transport, Transport.bluetooth);
    expect(
      find.byIcon(Icons.link),
      findsOneWidget,
      reason: 'a different target medium does not change the link button',
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.computer)).color,
      deviceColor('bt-computer'),
    );

    await tester.tap(find.byIcon(Icons.link));
    await tester.pumpAndSettle();
    expect(find.byType(TransportSheet), findsOneWidget);
    expect(find.text('Bluetooth computer: send input over'), findsOneWidget);
  });
}
