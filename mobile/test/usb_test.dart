import 'package:deskctrl/connection.dart';
import 'package:deskctrl/links.dart';
import 'package:deskctrl/scan_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/usb_pairing.dart';
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
  late FakeAgent agent;
  final c = Connection.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    Link.deadAfter = const Duration(seconds: 2);
    agent = await FakeAgent.start(
      'tok',
    ); // reachable at 127.0.0.1 like the cable's tunnel
  });

  tearDown(() async {
    await c.disconnectAll();
    await agent.server.close(force: true);
  });

  String link({String extra = 'usb=1', String name = 'Laptop'}) =>
      'deskctrl://pair/tok?$extra&port=${agent.port}&name=$name';

  String info(
    int port, {
    String bt = '',
    String ip = '127.0.0.1',
    String id = 'C0FFEE0000000001',
  }) =>
      'id=$id&port=$port&name=Laptop${ip.isEmpty ? '' : '&ip=$ip'}${bt.isEmpty ? '' : '&bt=$bt'}';

  test(
    'the link the agent sends is understood; a QR code is not mistaken for it',
    () {
      final u = PairInfo.parse(link())!;
      expect(u.usb, isTrue);
      expect((u.token, u.port, u.name), ('tok', agent.port, 'Laptop'));
      expect(u.ip, isNull);
      final qr = PairInfo.parse('deskctrl://pair/tok?ip=10.0.0.5&port=8765')!;
      expect(qr.usb, isFalse);
      expect(
        PairInfo.parse('deskctrl://pair/tok?port=8765'),
        isNull,
        reason: 'needs ip, bt or usb',
      );
    },
  );

  test(
    'plugging in pairs a new computer by itself and connects over the cable',
    () async {
      expect(Settings.instance.devices, isEmpty);
      expect(await UsbPairing.handle(link()), isTrue);
      final d = Settings.instance.devices.single;
      expect(
        (d.name, d.useUsb, d.useWifi, d.token),
        ('Laptop', true, false, 'tok'),
      );

      final s = c.session(d);
      await waitFor('USB link up', () => s.usb.connected);
      expect(s.effective!.transport, Transport.usb);
      expect(c.activeId, d.id, reason: 'it becomes the computer you are using');
      expect(s.wifi.connected, isFalse, reason: 'no Wi-Fi involved');

      c.key(0x04, true); // typing goes out over the cable
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(agent.received, contains('1,0,4'));
    },
  );

  test('a link without usb=1 is ignored (it could point the phone at another computer)', () async {
    expect(
      await UsbPairing.handle('deskctrl://pair/tok?ip=10.9.9.9&port=8765'),
      isFalse,
    );
    expect(await UsbPairing.handle('https://example.com'), isFalse);
    expect(Settings.instance.devices, isEmpty);
  });

  test('plugging in again does not add the computer twice', () async {
    await UsbPairing.handle(link());
    await UsbPairing.handle(link());
    expect(Settings.instance.devices.length, 1);
  });

  test('a computer already known over Wi-Fi gets the cable as a third link, with fail-over', () async {
    Settings.instance.saveDevice(
      Device(
        id: 'known',
        name: 'Desk',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await c.connectDevice('known');
    final s = c.session(Settings.instance.deviceById('known')!);
    await waitFor('Wi-Fi up', () => s.wifi.connected);
    expect(s.effective!.transport, Transport.wifi);

    await UsbPairing.handle(
      link(name: 'Other'),
    ); // same token = the same computer
    expect(Settings.instance.devices.length, 1);
    expect(Settings.instance.deviceById('known')!.useUsb, isTrue);
    expect(
      Settings.instance.deviceById('known')!.name,
      'Desk',
      reason: 'keeps its name',
    );
    await waitFor('USB link up', () => s.usb.connected);
    expect(
      s.effective!.transport,
      Transport.usb,
      reason: 'the cable wins while plugged in',
    );
    expect(
      s.usingFallback,
      isFalse,
      reason: 'using the cable is not a fall-back',
    );

    // Unplugged: the cable's link drops, traffic carries on over Wi-Fi.
    agent.socket!.close(); // the most recent connection is the cable's
    await waitFor('cable link gone', () => !s.usb.connected);
    expect(s.wifi.connected, isTrue);
    expect(s.effective!.transport, Transport.wifi);
    agent.received.clear();
    c.key(0x05, true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      agent.received,
      contains('1,0,5'),
      reason: 'typing still reaches the computer',
    );
  });

  test(
    'the cable link reconnects by itself when it is plugged in again',
    () async {
      await UsbPairing.handle(link());
      final s = c.session(Settings.instance.devices.single);
      await waitFor('USB link up', () => s.usb.connected);
      agent.socket!.close();
      await waitFor('cable link gone', () => !s.usb.connected);
      await waitFor('cable link back', () => s.usb.connected, seconds: 15);
    },
  );

  group('USB tells the phone how to reach the computer by Wi-Fi and Bluetooth', () {
    test(
      'Wi-Fi is set up by itself, and takes over when the cable is pulled out',
      () async {
        agent.info = info(agent.port);
        await UsbPairing.handle(link());
        final d = Settings.instance.devices.single;
        expect(d.useWifi, isFalse, reason: 'only the cable at first');
        final s = c.session(d);
        await waitFor(
          'Wi-Fi set up and connected',
          () => d.useWifi && s.wifi.connected,
        );
        expect(
          (d.host, d.port, d.computerId),
          ('127.0.0.1', agent.port, 'C0FFEE0000000001'),
        );
        expect(s.usb.connected, isTrue);
        expect(s.effective!.transport, Transport.usb);
        expect(Settings.instance.devices.length, 1);

        // Pull the cable out: no scanning, no tapping - Wi-Fi carries on.
        agent.sockets.first.close(); // the cable's connection came first
        await waitFor('cable gone', () => !s.usb.connected);
        expect(s.effective!.transport, Transport.wifi);
        agent.received.clear();
        c.key(0x07, true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(agent.received, contains('1,0,7'));
      },
    );

    test('with the setting off, only the cable is set up (the id is still remembered)', () async {
      Settings.instance.update(() => Settings.instance.usbSync = false);
      agent.info = info(agent.port);
      await UsbPairing.handle(link());
      final d = Settings.instance.devices.single;
      final s = c.session(d);
      await waitFor('cable up', () => s.usb.connected);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(d.useWifi, isFalse);
      expect(d.host, isEmpty);
      expect(s.wifi.state, LinkState.disconnected);
      expect(
        d.computerId,
        'C0FFEE0000000001',
        reason: 'so it is not added twice',
      );
    });

    test(
      'Bluetooth is set up when the computer is paired with the phone',
      () async {
        const addr = 'AA:BB:CC:DD:EE:FF';
        final bt = FakeBt('tok')..install();
        addTearDown(bt.uninstall);
        bt.bonded.add(('Laptop', addr));
        agent.info = info(agent.port, bt: addr, ip: '');
        await UsbPairing.handle(link());
        final d = Settings.instance.devices.single;
        final s = c.session(d);
        await waitFor(
          'Bluetooth set up and connected',
          () => d.useBt && s.bt.connected,
        );
        expect((d.btAddress, d.btName), (addr, 'Laptop'));
        expect(s.syncNote, isNull);
      },
    );

    test('Bluetooth not paired: the phone says what to do, and nothing else breaks', () async {
      final bt = FakeBt('tok')..install();
      addTearDown(bt.uninstall);
      agent.info = info(agent.port, bt: 'AA:BB:CC:DD:EE:FF');
      await UsbPairing.handle(link());
      final d = Settings.instance.devices.single;
      final s = c.session(d);
      await waitFor('Wi-Fi up', () => s.wifi.connected);
      await waitFor('a note', () => s.syncNote != null);
      expect(s.syncNote, contains('pair this phone with the computer'));
      expect(d.useBt, isFalse);
      expect(s.usb.connected && s.wifi.connected, isTrue);
    });

    test('information that arrives over Wi-Fi is ignored: only the cable is trusted', () async {
      agent.info = '${info(agent.port, ip: '10.9.9.9')}&x=1';
      Settings.instance.saveDevice(
        Device(
          id: 'w',
          name: 'Desk',
          host: '127.0.0.1',
          port: agent.port,
          token: 'tok',
        ),
      );
      await c.connectDevice('w');
      final d = Settings.instance.deviceById('w')!;
      await waitFor('Wi-Fi up', () => c.session(d).wifi.connected);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        d.host,
        '127.0.0.1',
        reason: 'a Wi-Fi link cannot redirect the computer',
      );
      expect(d.computerId, isEmpty);
    });
  });

  group('the same computer is never added twice', () {
    test('findSame: id, token, Wi-Fi address and Bluetooth device', () async {
      final st = Settings.instance;
      st.saveDevice(
        Device(
          id: 'a',
          name: 'A',
          host: '10.0.0.5',
          port: 8765,
          token: 't1',
          computerId: 'ID1',
          btAddress: 'AA:BB:CC:DD:EE:FF',
        ),
      );
      Device probe({
        String id = '',
        String token = '',
        String host = '',
        int port = 8765,
        String bt = '',
      }) => Device(
        id: 'new',
        computerId: id,
        token: token,
        host: host,
        port: port,
        btAddress: bt,
      );
      expect(
        st.findSame(probe(id: 'ID1'))?.id,
        'a',
        reason: 'same computer id',
      );
      expect(st.findSame(probe(token: 't1'))?.id, 'a', reason: 'same token');
      expect(
        st.findSame(probe(host: '10.0.0.5'))?.id,
        'a',
        reason: 'same address and port',
      );
      expect(
        st.findSame(probe(bt: 'aa:bb:cc:dd:ee:ff'))?.id,
        'a',
        reason: 'same Bluetooth device',
      );
      expect(
        st.findSame(probe(host: '10.0.0.5', port: 9000)),
        isNull,
        reason: 'another port is another agent',
      );
      expect(
        st.findSame(probe(id: 'OTHER', token: 'other', host: '10.0.0.9')),
        isNull,
      );
      expect(
        st.findSame(Device(id: 'a', computerId: 'ID1')),
        isNull,
        reason: 'not itself',
      );
    });

    test('plugging in a computer that is in the list by Wi-Fi joins the two entries', () async {
      // Added by hand over Wi-Fi earlier, with a token the agent no longer has.
      Settings.instance.saveDevice(
        Device(
          id: 'old',
          name: 'Desk',
          host: '127.0.0.1',
          port: agent.port,
          token: 'stale',
        ),
      );
      agent.info =
          'id=C0FFEE0000000001&port=${agent.port}&name=Laptop&ip=127.0.0.1';
      await UsbPairing.handle(link()); // the cable brings the current token
      await waitFor(
        'one entry left',
        () => Settings.instance.devices.length == 1,
        seconds: 15,
      );
      final d = Settings.instance.devices.single;
      expect(d.id, 'old', reason: 'the entry that was there first stays');
      expect(
        (d.name, d.token, d.useUsb, d.useWifi),
        ('Desk', 'tok', true, true),
      );
      expect(d.computerId, 'C0FFEE0000000001');
      final s = c.session(d);
      await waitFor(
        'connected',
        () => s.usb.connected && s.wifi.connected,
        seconds: 15,
      );
      expect(c.activeId, 'old');
    });

    test('the agent restarted with a new token: the same computer is updated, not added again', () async {
      Settings.instance.saveDevice(
        Device(
          id: 'known',
          name: 'Desk',
          host: '127.0.0.1',
          port: agent.port,
          token: 'old-token',
          computerId: 'C0FFEE0000000001',
        ),
      );
      await UsbPairing.handle(
        link(extra: 'usb=1&id=C0FFEE0000000001'),
      ); // token 'tok', same computer id
      expect(Settings.instance.devices.length, 1);
      final d = Settings.instance.devices.single;
      expect((d.id, d.token), ('known', 'tok'));
      final s = c.session(d);
      await waitFor(
        'connected with the new token',
        () => s.usb.connected,
        seconds: 15,
      );
    });

    test('unplugged and plugged in again: still one computer', () async {
      agent.info = info(agent.port);
      await UsbPairing.handle(link());
      final s = c.session(Settings.instance.devices.single);
      await waitFor('up', () => s.usb.connected && s.wifi.connected);
      agent.sockets.first.close();
      await waitFor('cable gone', () => !s.usb.connected);
      await UsbPairing.handle(link()); // plugged in again
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(Settings.instance.devices.length, 1);
    });

    test(
      'adding by hand what is already there updates it (the form uses this)',
      () {
        final st = Settings.instance;
        st.saveDevice(
          Device(
            id: 'a',
            name: 'Desk',
            host: '10.0.0.5',
            port: 8765,
            token: 't1',
            computerId: 'ID1',
            useUsb: true,
          ),
        );
        final typed = Device(
          id: 'b',
          name: 'Computer 2',
          host: '10.0.0.5',
          port: 8765,
          token: 't2',
          btAddress: 'AA:BB:CC:DD:EE:FF',
          btName: 'Desk BT',
          useBt: true,
        );
        final dup = st.findSame(typed)!;
        Connection.mergeFields(dup, typed);
        expect(
          (dup.id, dup.name),
          ('a', 'Desk'),
          reason: 'keeps its place and name',
        );
        expect(
          (dup.token, dup.useBt, dup.btAddress, dup.useUsb, dup.computerId),
          ('t2', true, 'AA:BB:CC:DD:EE:FF', true, 'ID1'),
        );
      },
    );

    test('entries that piled up before are joined, keeping the first one and the newest token', () async {
      final st = Settings.instance;
      // Added at different times (the id is the time): the same computer three times.
      st.saveDevice(
        Device(
          id: '1000',
          name: 'Computer 2',
          host: '10.0.0.5',
          port: 8765,
          token: 'old',
        ),
      );
      st.saveDevice(
        Device(
          id: '2000',
          name: 'test',
          host: '10.0.0.5',
          port: 8765,
          token: 'newer',
          useUsb: true,
        ),
      );
      st.saveDevice(
        Device(
          id: '3000',
          name: 'test',
          token: 'newest',
          useUsb: true,
          computerId: 'ID9',
        ),
      );
      st.saveDevice(
        Device(
          id: '4000',
          name: 'Other PC',
          host: '10.0.0.77',
          port: 8765,
          token: 'x',
        ),
      );
      final joined = await c.dedupeAll();
      expect(joined, 1, reason: 'only the first two are provably the same');
      expect(st.devices.map((d) => d.id), ['1000', '3000', '4000']);
      final d = st.deviceById('1000')!;
      expect(
        (d.name, d.token, d.useUsb),
        ('Computer 2', 'newer', true),
        reason: 'its name, the newer token',
      );
      expect(await c.dedupeAll(), 0, reason: 'nothing left to join');
    });

    test('a computer that turns out to be one already in the list is joined, however it got there', () async {
      final st = Settings.instance;
      st.saveDevice(
        Device(
          id: '1000',
          name: 'Desk',
          host: '127.0.0.1',
          port: agent.port,
          token: 'stale',
        ),
      );
      st.saveDevice(
        Device(
          id: '1500',
          name: 'Desk (Wi-Fi)',
          host: '127.0.0.1',
          port: agent.port,
          token: 'staler',
        ),
      );
      agent.info =
          'id=C0FFEE0000000001&port=${agent.port}&name=Laptop&ip=127.0.0.1';
      await UsbPairing.handle(link());
      await waitFor(
        'one entry left',
        () => st.devices.length == 1,
        seconds: 15,
      );
      await Future<void>.delayed(
        const Duration(seconds: 2),
      ); // and it stays that way
      expect(st.devices.single.id, '1000');
      expect(st.devices.single.token, 'tok');
    });
  });
}
