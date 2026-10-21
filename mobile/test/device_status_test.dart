import 'package:deskctrl/connection.dart';
import 'package:deskctrl/devices_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'the status shows which links are up, which are down, and when everything is lost',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      final d = Device(
        id: 'status',
        name: 'Laptop',
        host: '1.2.3.4',
        useBt: true,
        btAddress: 'AA:BB',
      );
      Settings.instance.saveDevice(d);
      final s = Connection.instance.session(d);
      s.phase = Phase.active;
      s.debugWant(Transport.wifi);
      s.debugWant(Transport.bluetooth);

      Future<void> show() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DeviceRow(device: d, onTap: () {}),
            ),
          ),
        );
      }

      s.wifi.setState(LinkState.connected);
      s.bt.setState(LinkState.connected);
      await show();
      expect(
        find.text('Connected - Wi-Fi + Bluetooth'),
        findsOneWidget,
        reason: 'both up',
      );

      s.wifi.setState(
        LinkState.disconnected,
        'No response from the PC',
      ); // Wi-Fi died
      await show();
      expect(
        find.text('Connected - Bluetooth (Wi-Fi down)'),
        findsOneWidget,
        reason: 'fail-over is visible',
      );

      s.bt.setState(LinkState.disconnected); // and now Bluetooth too
      await show();
      expect(find.text('Connection lost - reconnecting...'), findsOneWidget);
      expect(
        find.textContaining('Connected -'),
        findsNothing,
        reason: 'never the empty "Connected -"',
      );

      // End the session so no timers are left running.
      s.phase = Phase.idle;
      s.wifi.setState(LinkState.disconnected);
    },
  );
}
