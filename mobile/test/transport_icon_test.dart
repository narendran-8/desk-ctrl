import 'package:deskctrl/connection.dart';
import 'package:deskctrl/links.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/usb_pairing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  usbToWifiIcon();
  testWidgets('the connection icon follows the link that carries the input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    Link.deadAfter = const Duration(seconds: 2);
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
    final bt = FakeBt('tok')..install();
    addTearDown(() async {
      Link.deadAfter = const Duration(milliseconds: 3500);
      await Connection.instance.disconnectAll();
      bt.uninstall();
      await agent.server.close(force: true);
    });
    Settings.instance.saveDevice(
      Device(
        id: 'ti',
        name: 'Laptop',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
        useWifi: true,
        useBt: true,
        btAddress: 'AA:BB:CC:DD:EE:FF',
        btName: 'Laptop',
      ),
    );
    final c = Connection.instance;
    await tester.runAsync(() => c.connectDevice('ti'));
    await tester.pumpWidget(const MaterialApp(home: Home()));

    Future<void> until(bool Function() cond) async {
      for (var i = 0; i < 100 && !cond(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    final s = c.active!;
    await until(() => s.wifi.connected && s.bt.connected);
    await tester.pump();
    expect(find.byIcon(Icons.wifi), findsOneWidget);

    agent.silent = true; // Wi-Fi stops answering
    await until(() => !s.wifi.connected);
    await tester.pump();
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsNothing);

    agent.silent = false;
    await until(() => s.wifi.connected);
    await tester.pump();
    expect(find.byIcon(Icons.wifi), findsOneWidget);
  });
}

void usbToWifiIcon() {
  testWidgets('USB first, cable pulled out: the icon goes from USB to Wi-Fi', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    Link.deadAfter = const Duration(seconds: 2);
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
        id: 'ui',
        name: 'Desk',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    final c = Connection.instance;
    await tester.runAsync(() => c.connectDevice('ui'));
    await tester.pumpWidget(const MaterialApp(home: Home()));
    final s = c.active!;

    Future<void> until(bool Function() cond) async {
      for (var i = 0; i < 100 && !cond(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    await until(() => s.wifi.connected);
    await tester.pump();
    expect(find.byIcon(Icons.wifi), findsOneWidget);

    // The cable is plugged in: the computer is already known, it gains the USB link.
    await tester.runAsync(
      () => UsbPairing.handle(
        'deskctrl://pair/tok?usb=1&port=${agent.port}&name=Desk',
      ),
    );
    await until(() => s.usb.connected);
    await tester.pump();
    expect(find.byIcon(Icons.usb), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsNothing);

    // Cable pulled out.
    await tester.runAsync(() async => agent.socket!.close());
    await until(() => !s.usb.connected);
    await tester.pump();
    expect(find.byIcon(Icons.wifi), findsOneWidget);
    expect(find.byIcon(Icons.usb), findsNothing);
  });

  testWidgets(
    'cable pulled out silently (nothing closes): USB turns to Wi-Fi within seconds',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      Link.deadAfter = const Duration(seconds: 2);
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
      agent.info =
          'id=C0FFEE0000000001&port=${agent.port}&name=Laptop&ip=127.0.0.1';
      addTearDown(() async {
        Link.deadAfter = const Duration(milliseconds: 3500);
        await Connection.instance.disconnectAll();
        await agent.server.close(force: true);
      });
      final c = Connection.instance;
      await tester.runAsync(
        () => UsbPairing.handle(
          'deskctrl://pair/tok?usb=1&port=${agent.port}&name=Laptop',
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: Home()));
      final s = c.active!;
      Future<void> until(bool Function() cond) async {
        for (var i = 0; i < 100 && !cond(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
      }

      await until(() => s.usb.connected && s.wifi.connected);
      await tester.pump();
      expect(find.byIcon(Icons.usb), findsOneWidget);

      agent.muted.add(agent.sockets.first); // the cable's connection
      await until(() => !s.usb.connected);
      await tester.pump();
      expect(s.usb.connected, isFalse);
      expect(find.byIcon(Icons.wifi), findsOneWidget);
      expect(find.byIcon(Icons.usb), findsNothing);
    },
  );

  testWidgets(
    'Android reports the cable gone: the icon moves to Wi-Fi at once',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      MockStreamHandlerEventSink? cable;
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('deskctrl/usb/state'),
        MockStreamHandler.inline(
          onListen: (_, sink) {
            cable = sink;
          },
          onCancel: (_) {
            cable = null;
          },
        ),
      );
      final agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
      agent.info =
          'id=C0FFEE0000000001&port=${agent.port}&name=Laptop&ip=127.0.0.1';
      addTearDown(() async {
        await Connection.instance.disconnectAll();
        await agent.server.close(force: true);
      });
      final c = Connection.instance;
      UsbPairing.watchCable();
      await tester.runAsync(
        () => UsbPairing.handle(
          'deskctrl://pair/tok?usb=1&port=${agent.port}&name=Laptop',
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: Home()));
      final s = c.active!;
      for (var i = 0; i < 100 && !(s.usb.connected && s.wifi.connected); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();
      expect(find.byIcon(Icons.usb), findsOneWidget);

      cable!.success(true); // plugged in
      await tester.pump();
      expect(s.usb.connected, isTrue);
      cable!.success(
        false,
      ); // pulled out; nothing was closed and no time passed
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(s.usb.connected, isFalse);
      expect(find.byIcon(Icons.wifi), findsOneWidget);
      expect(find.byIcon(Icons.usb), findsNothing);
      await tester.runAsync(c.disconnectAll); // no retry timers left behind
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'side-bar layout (const buttons): the icon still follows the link',
    (tester) async {
      SharedPreferences.setMockInitialValues({'sideBar': true});
      await Settings.instance.load();
      tester.view.physicalSize = const Size(1640, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
      agent.info =
          'id=C0FFEE0000000001&port=${agent.port}&name=Laptop&ip=127.0.0.1';
      addTearDown(() async {
        await Connection.instance.disconnectAll();
        await agent.server.close(force: true);
      });
      final c = Connection.instance;
      await tester.runAsync(
        () => UsbPairing.handle(
          'deskctrl://pair/tok?usb=1&port=${agent.port}&name=Laptop',
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: Home()));
      final s = c.active!;
      for (var i = 0; i < 100 && !(s.usb.connected && s.wifi.connected); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();
      expect(find.byIcon(Icons.usb), findsOneWidget);
      await tester.runAsync(() async => s.usb.cableRemoved());
      await tester.pump();
      expect(find.byIcon(Icons.wifi), findsOneWidget);
      expect(find.byIcon(Icons.usb), findsNothing);
      await tester.runAsync(c.disconnectAll);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
