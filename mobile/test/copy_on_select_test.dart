import 'package:deskctrl/connection.dart';
import 'package:deskctrl/main.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  late FakeAgent agent;
  final c = Connection.instance;
  var copied = 0;

  Future<void> pause(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    agent = await FakeAgent.start('tok');
    Settings.instance.saveDevice(
      Device(
        id: 'cs',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await c.switchTo('cs');
    await pause(300);
    copied = 0;
    c.onCopied = () => copied++;
  });

  tearDown(() async {
    c.onCopied = null;
    await c.disconnectAll();
    await agent.server.close(force: true);
  });

  // Ctrl down, Insert down, Insert up, Ctrl up.
  const ctrlInsert = ['1,0,224', '1,0,73', '2,0,73', '2,0,224'];
  List<String> keys() => [
    for (final m in agent.received)
      if (m.startsWith('1,') || m.startsWith('2,')) m,
  ];

  test('a drag with the left button copies the selection', () async {
    c.button(0, true);
    c.move(30, 5);
    c.button(0, false);
    await pause(400);
    expect(keys(), ctrlInsert);
    expect(copied, 1);
  });

  test('a plain click does not copy; a double click does', () async {
    c.click(0);
    await pause(300);
    expect(keys(), isEmpty);
    c.click(0);
    await pause(400);
    expect(keys(), ctrlInsert);
    expect(copied, 1);
  });

  test(
    'a drag with the right button, or with the setting off, does not copy',
    () async {
      c.button(1, true);
      c.move(50, 0);
      c.button(1, false);
      Settings.instance.update(() => Settings.instance.copyOnSelect = false);
      c.button(0, true);
      c.move(50, 0);
      c.button(0, false);
      await pause(400);
      expect(keys(), isEmpty);
      expect(copied, 0);
    },
  );

  testWidgets('the app shows a small "Copied" message', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Home()));
    await tester.pump();
    final toast = find.byKey(const Key('copiedToast'));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: toast, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0,
    );
    await tester.runAsync(() async {
      c.button(0, true);
      c.move(40, 0);
      c.button(0, false);
      await pause(400);
    });
    await tester.pump();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: toast, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      1,
    );
    await tester.runAsync(
      () => pause(1700),
    ); // the message fades after a moment
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: toast, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0,
    );
  });
}
