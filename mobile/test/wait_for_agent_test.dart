import 'dart:convert';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  test(
    'the app opened first connects by itself once the agent starts',
    () async {
      final probe = await FakeAgent.start('t');
      final port = probe.port;
      await probe.server.close(force: true); // no agent running yet

      SharedPreferences.setMockInitialValues({
        'devices': jsonEncode([
          Device(
            id: 'pc',
            name: 'PC',
            host: '127.0.0.1',
            port: port,
            token: 't',
          ).toJson(),
        ]),
        'lastConnected': ['pc'],
        'lastActiveId': 'pc',
      });
      await Settings.instance.load();
      Session.waitInterval = const Duration(milliseconds: 200);

      final c = Connection.instance;
      await c.restoreLast(); // the app starts: nothing answers
      expect(c.activeCount, 0);

      final agent = await FakeAgent.start(
        't',
        port: port,
      ); // the agent is opened
      for (var i = 0; i < 40 && c.activeCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        c.activeCount,
        1,
        reason: 'found the agent without a scan or cable',
      );
      expect(c.activeId, 'pc');

      c.key(4, true);
      await settle();
      expect(agent.received, ['1,0,4']);
      await c.disconnectAll();
    },
  );

  test('a computer disconnected by hand is not looked for', () async {
    final probe = await FakeAgent.start('t');
    final port = probe.port;
    await probe.server.close(force: true);
    SharedPreferences.setMockInitialValues({
      'devices': jsonEncode([
        Device(
          id: 'pc',
          name: 'PC',
          host: '127.0.0.1',
          port: port,
          token: 't',
        ).toJson(),
      ]),
      'lastConnected': ['pc'],
    });
    await Settings.instance.load();
    Session.waitInterval = const Duration(milliseconds: 200);
    final c = Connection.instance;
    await c.restoreLast();
    await c.disconnectDevice('pc');
    final agent = await FakeAgent.start('t', port: port);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(c.activeCount, 0);
    expect(agent.connections, 0);
  });

  test('an agent that was started with a new token is reported, not retried silently', () async {
    final agent = await FakeAgent.start('the-new-token');
    SharedPreferences.setMockInitialValues({
      'devices': jsonEncode([
        Device(
          id: 'pc',
          name: 'PC',
          host: '127.0.0.1',
          port: agent.port,
          token: 'the-old-token',
        ).toJson(),
      ]),
      'lastConnected': ['pc'],
    });
    await Settings.instance.load();
    Session.waitInterval = const Duration(milliseconds: 200);
    final c = Connection.instance;
    await c.restoreLast();
    for (var i = 0; i < 30 && !(c.active?.tokenRejected ?? false); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(c.active?.tokenRejected, isTrue);
    expect(c.active?.waiting, isTrue);
    expect(c.activeCount, 0);
    await c.disconnectAll();
    await agent.server.close(force: true);
  });
}
