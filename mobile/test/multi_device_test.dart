import 'dart:convert';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/settings.dart';

import 'fake_agent.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('two computers stay connected; switching sends input to the right one without reconnecting', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    final laptop = await FakeAgent.start('tok-laptop');
    final pc = await FakeAgent.start('tok-pc');
    Settings.instance
      ..saveDevice(
        Device(
          id: 'laptop',
          name: 'Laptop',
          host: '127.0.0.1',
          port: laptop.port,
          token: 'tok-laptop',
        ),
      )
      ..saveDevice(
        Device(
          id: 'pc',
          name: 'PC',
          host: '127.0.0.1',
          port: pc.port,
          token: 'tok-pc',
        ),
      );

    final c = Connection.instance;
    await c.connectAll();
    expect(c.activeCount, 2, reason: 'both computers connected at once');

    await c.switchTo('laptop');
    c.key(4, true); // A down, on the laptop
    await settle();
    expect(laptop.received, ['1,0,4']);
    expect(pc.received, isEmpty);

    // Switch while the key is still held: the laptop must get the release.
    await c.switchTo('pc');
    c.key(5, true);
    c.key(5, false);
    await settle();
    expect(laptop.received, [
      '1,0,4',
      '2,0,4',
    ], reason: 'held key released on the computer we left');
    expect(pc.received, ['1,0,5', '2,0,5']);

    // Back and forth did not reconnect anything.
    await c.switchTo('laptop');
    c.click(0);
    await settle();
    expect(laptop.received.last, '4,0,0');
    expect(laptop.connections, 1);
    expect(pc.connections, 1);

    // Disconnecting the active computer hands focus to the other one.
    await c.disconnectDevice('laptop');
    expect(c.activeId, 'pc');
    expect(c.activeCount, 1);

    await c.disconnectAll();
    await laptop.server.close(force: true);
    await pc.server.close(force: true);
  });

  test('a wrong token fails that computer only', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    final good = await FakeAgent.start('right');
    final bad = await FakeAgent.start('right');
    Settings.instance
      ..saveDevice(
        Device(
          id: 'g',
          name: 'Good',
          host: '127.0.0.1',
          port: good.port,
          token: 'right',
        ),
      )
      ..saveDevice(
        Device(
          id: 'b',
          name: 'Bad',
          host: '127.0.0.1',
          port: bad.port,
          token: 'wrong',
        ),
      );

    final c = Connection.instance;
    await c.connectAll();
    expect(c.session(Settings.instance.deviceById('g')!).phase, Phase.active);
    final b = c.session(Settings.instance.deviceById('b')!);
    expect(b.phase, Phase.idle);
    expect(b.error, contains('wrong token'));

    await c.disconnectAll();
    await good.server.close(force: true);
    await bad.server.close(force: true);
  });

  test('Caps Lock light follows the computer, with a fallback when none is reported', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    final withLeds = await FakeAgent.start('t1', leds: 0x01); // Caps already on
    final noLeds = await FakeAgent.start('t2');
    Settings.instance
      ..saveDevice(
        Device(
          id: 'l',
          name: 'Reports',
          host: '127.0.0.1',
          port: withLeds.port,
          token: 't1',
        ),
      )
      ..saveDevice(
        Device(
          id: 'n',
          name: 'Silent',
          host: '127.0.0.1',
          port: noLeds.port,
          token: 't2',
        ),
      );
    final c = Connection.instance;

    await c.switchTo('l');
    await settle();
    expect(c.capsOn, isTrue, reason: 'lit from the first report');

    withLeds.socket!.add(<int>[0x10, 0x00]); // Caps turned off on the computer
    await settle();
    expect(c.capsOn, isFalse);
    withLeds.socket!.add(<int>[0x10, 0x03]); // Caps + Num on
    await settle();
    expect(c.capsOn, isTrue);

    // A computer that reports nothing: count Caps presses instead.
    await c.switchTo('n');
    await settle();
    expect(c.capsOn, isFalse);
    c.key(0x39, true);
    c.key(0x39, false);
    expect(c.capsOn, isTrue);
    c.key(0x39, true);
    c.key(0x39, false);
    expect(c.capsOn, isFalse);

    await c.disconnectAll();
    await withLeds.server.close(force: true);
    await noLeds.server.close(force: true);
  });

  test(
    'media keys (brightness, volume) go out with their full 16-bit code',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      final pc = await FakeAgent.start('tok');
      Settings.instance.saveDevice(
        Device(
          id: 'pc',
          name: 'PC',
          host: '127.0.0.1',
          port: pc.port,
          token: 'tok',
        ),
      );
      final c = Connection.instance;
      await c.switchTo('pc');
      await settle();

      c.key(0x806F, true); // brightness up
      c.key(0x806F, false);
      await settle();
      expect(pc.received, ['1,128,111', '2,128,111']);

      await c.disconnectAll();
      await pc.server.close(force: true);
    },
  );

  group('remember last connected computers', () {
    Future<void> prefs(
      List<Device> devices,
      List<String> last,
      String active, {
      bool auto = true,
    }) async {
      SharedPreferences.setMockInitialValues({
        'devices': jsonEncode([for (final d in devices) d.toJson()]),
        'lastConnected': last,
        'lastActiveId': active,
        'autoReconnect': auto,
      });
      await Settings.instance.load(); // what happens when the app starts
    }

    test(
      'a restart reconnects both computers and puts the last-used one in focus',
      () async {
        final a = await FakeAgent.start('ta');
        final b = await FakeAgent.start('tb');
        await prefs(
          [
            Device(
              id: 'r1',
              name: 'Laptop',
              host: '127.0.0.1',
              port: a.port,
              token: 'ta',
            ),
            Device(
              id: 'r2',
              name: 'PC',
              host: '127.0.0.1',
              port: b.port,
              token: 'tb',
            ),
          ],
          ['r1', 'r2'],
          'r2',
        );

        final c = Connection.instance;
        await c.restoreLast();
        await settle();
        expect(c.activeCount, 2);
        expect(
          c.activeId,
          'r2',
          reason: 'the computer used last gets the input',
        );

        c.key(4, true);
        c.key(4, false);
        await settle();
        expect(b.received, ['1,0,4', '2,0,4']);
        expect(a.received, isEmpty);

        // Switching is remembered too.
        await c.switchTo('r1');
        expect(Settings.instance.lastActiveId, 'r1');

        // Disconnecting one by hand means it is not reconnected next time.
        await c.disconnectDevice('r2');
        expect(Settings.instance.lastConnected, ['r1']);

        await c.disconnectAll();
        expect(Settings.instance.lastConnected, isEmpty);
        await a.server.close(force: true);
        await b.server.close(force: true);
      },
    );

    test('a computer that is off at start does not block the others', () async {
      final up = await FakeAgent.start('tu');
      final down = await FakeAgent.start('td');
      final downPort = down.port;
      await down.server.close(force: true); // nothing listens there any more
      await prefs(
        [
          Device(
            id: 'u1',
            name: 'Up',
            host: '127.0.0.1',
            port: up.port,
            token: 'tu',
          ),
          Device(
            id: 'd1',
            name: 'Off',
            host: '127.0.0.1',
            port: downPort,
            token: 'td',
          ),
        ],
        ['u1', 'd1'],
        'd1',
      );

      final c = Connection.instance;
      await c.restoreLast();
      await settle();
      expect(
        c.session(Settings.instance.deviceById('u1')!).phase,
        Phase.active,
      );
      expect(
        c.activeId,
        'u1',
        reason: 'focus moves to a computer that is actually up',
      );
      expect(
        Settings.instance.lastConnected,
        contains('d1'),
        reason: 'a failed attempt must not make the app forget it',
      );

      await c.disconnectAll();
      await up.server.close(force: true);
    });

    test(
      'does nothing when "Reconnect on start" is off or nothing was connected',
      () async {
        final a = await FakeAgent.start('tx');
        final dev = Device(
          id: 'x1',
          name: 'X',
          host: '127.0.0.1',
          port: a.port,
          token: 'tx',
        );
        await prefs([dev], ['x1'], 'x1', auto: false);
        await Connection.instance.restoreLast();
        await settle();
        expect(a.connections, 0);

        await prefs([dev], [], '');
        await Connection.instance.restoreLast();
        await settle();
        expect(a.connections, 0);
        await a.server.close(force: true);
      },
    );
  });
}
