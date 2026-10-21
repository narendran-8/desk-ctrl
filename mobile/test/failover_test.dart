import 'package:deskctrl/connection.dart';
import 'package:deskctrl/links.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

Future<void> waitFor(
  String what,
  bool Function() cond, {
  int seconds = 10,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for: $what');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const btAddress = 'AA:BB:CC:DD:EE:FF';
  late FakeAgent agent; // the Wi-Fi side of the computer
  late FakeBt bt; // the Bluetooth side of the same computer
  late Session s;
  final c = Connection.instance;
  var n = 0;

  Future<void> connect({String preferred = 'wifi'}) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    Link.deadAfter = const Duration(
      seconds: 2,
    ); // the app uses 3.5 s; shorter keeps the test quick
    agent = await FakeAgent.start('tok');
    bt = FakeBt('tok')..install();
    final id = 'laptop-${n++}';
    Settings.instance.saveDevice(
      Device(
        id: id,
        name: 'Laptop',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
        useWifi: true,
        useBt: true,
        btAddress: btAddress,
        btName: 'Laptop',
        transport: preferred,
      ),
    );
    await c.connectDevice(id);
    s = c.session(Settings.instance.deviceById(id)!);
    await waitFor('both links up', () => s.wifi.connected && s.bt.connected);
  }

  Future<void> deliver() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  tearDown(() async {
    Link.deadAfter = const Duration(milliseconds: 3500);
    await c.disconnectAll();
    bt.uninstall();
    await agent.server.close(force: true);
  });

  test('Wi-Fi dies silently: typing moves to Bluetooth by itself, and back when Wi-Fi returns', () async {
    await connect();
    expect(s.effective!.transport, Transport.wifi);
    c.key(4, true);
    c.key(4, false);
    await deliver();
    expect(agent.received, ['1,0,4', '2,0,4'], reason: 'normally over Wi-Fi');
    expect(bt.written, isEmpty);

    // The laptop's Wi-Fi goes off. Nothing is closed: it just stops answering.
    agent.silent = true;
    await waitFor('Wi-Fi declared dead', () => !s.wifi.connected);
    expect(s.phase, Phase.active, reason: 'the session is not lost');
    expect(
      s.effective!.transport,
      Transport.bluetooth,
      reason: 'traffic moved to Bluetooth',
    );
    expect(s.usingFallback, isTrue);
    c.key(5, true);
    c.key(5, false);
    await deliver();
    expect(bt.written, [
      '1,0,5',
      '2,0,5',
    ], reason: 'typing works over Bluetooth');

    // Wi-Fi comes back: the app reconnects it in the background and returns to it.
    agent.silent = false;
    await waitFor('Wi-Fi reconnected', () => s.wifi.connected, seconds: 20);
    expect(s.effective!.transport, Transport.wifi);
    c.key(6, true);
    c.key(6, false);
    await deliver();
    expect(agent.received.sublist(agent.received.length - 2), [
      '1,0,6',
      '2,0,6',
    ], reason: 'back on Wi-Fi');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
    'a key held when Wi-Fi dies is released on the link that takes over',
    () async {
      await connect();
      c.key(4, true); // finger down on a key ... then the Wi-Fi link dies
      await deliver();
      expect(agent.received, ['1,0,4']);

      agent.silent = true;
      await waitFor('Wi-Fi declared dead', () => !s.wifi.connected);
      await deliver();
      expect(
        bt.written,
        contains('2,0,4'),
        reason: 'the key is released over Bluetooth, so it cannot stick down',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('Bluetooth dies instead: typing moves to Wi-Fi', () async {
    await connect(preferred: 'bluetooth');
    expect(s.effective!.transport, Transport.bluetooth);
    c.key(7, true);
    c.key(7, false);
    await deliver();
    expect(bt.written, ['1,0,7', '2,0,7']);

    bt.silent = true; // out of range
    await waitFor('Bluetooth declared dead', () => !s.bt.connected);
    expect(s.phase, Phase.active);
    expect(s.effective!.transport, Transport.wifi);
    c.key(8, true);
    c.key(8, false);
    await deliver();
    expect(agent.received, ['1,0,8', '2,0,8'], reason: 'now over Wi-Fi');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'both links down: the session survives and recovers when one comes back',
    () async {
      await connect();
      agent.silent = true;
      bt.silent = true;
      await waitFor(
        'both declared dead',
        () => !s.wifi.connected && !s.bt.connected,
      );
      expect(s.effective, isNull, reason: 'nothing to send on right now');
      expect(
        s.phase,
        Phase.active,
        reason: 'but the session is kept and keeps retrying',
      );

      bt.silent = false; // Bluetooth is back
      await waitFor('Bluetooth reconnected', () => s.bt.connected, seconds: 20);
      expect(s.effective!.transport, Transport.bluetooth);
      c.key(9, true);
      c.key(9, false);
      await deliver();
      expect(bt.written, contains('1,0,9'));
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'a healthy link is not dropped just because the computer is quiet',
    () async {
      await connect();
      // Nothing typed for longer than the dead-link time; heartbeats keep both links up.
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(s.wifi.connected && s.bt.connected, isTrue);
      expect(agent.connections, 1, reason: 'no reconnecting happened');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'an older agent that sends no heartbeats is not mistaken for a dead link',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      Link.deadAfter = const Duration(seconds: 1);
      agent = await FakeAgent.start('tok', heartbeats: false);
      bt = FakeBt('tok')..install();
      Settings.instance.saveDevice(
        Device(
          id: 'older',
          name: 'Old',
          host: '127.0.0.1',
          port: agent.port,
          token: 'tok',
        ),
      );
      await c.connectDevice('older');
      s = c.session(Settings.instance.deviceById('older')!);
      await waitFor('Wi-Fi up', () => s.wifi.connected);
      await Future<void>.delayed(
        const Duration(seconds: 4),
      ); // four times the dead-link time
      expect(
        s.wifi.connected,
        isTrue,
        reason: 'no heartbeat support: the old behaviour is kept',
      );
      expect(agent.connections, 1, reason: 'and it did not reconnect');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
