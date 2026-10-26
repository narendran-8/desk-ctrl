import 'dart:convert';
import 'dart:typed_data';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/now_playing.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  test('formats current/total times including hours', () {
    expect(playbackTime(65000), '1:05');
    expect(playbackTime(3723000), '1:02:03');
    expect(playbackTime(-1), '0:00');
  });
  test('position advances at playback rate, pauses and clamps to duration', () {
    final now = DateTime(2026);
    final playing = NowPlaying(
      positionMs: 10000,
      durationMs: 15000,
      playing: true,
      rate: 2,
      receivedAt: now,
    );
    expect(playing.positionAt(now.add(const Duration(seconds: 1))), 12000);
    expect(playing.positionAt(now.add(const Duration(seconds: 4))), 15000);
    final paused = NowPlaying(
      positionMs: 10000,
      durationMs: 15000,
      receivedAt: now,
    );
    expect(paused.positionAt(now.add(const Duration(seconds: 3))), 10000);
  });
  testWidgets(
    'red playhead/played track, grey remainder and live seek disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: MediaTimeline(
                media: const NowPlaying(positionMs: 15000, durationMs: 90000),
                onSeek: (_, _) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('0:15'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      final theme = tester.widget<SliderTheme>(find.byType(SliderTheme));
      expect(theme.data.activeTrackColor, Colors.red);
      expect(theme.data.thumbColor, Colors.red);
      expect(theme.data.inactiveTrackColor, Colors.grey.shade700);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: MediaTimeline(
                media: const NowPlaying(positionMs: 5000),
                onSeek: (_, _) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('LIVE'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    },
  );
  testWidgets('drag sends one absolute seek and no mouse/key events', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    final agent = (await tester.runAsync(() => FakeAgent.start('timeline')))!;
    addTearDown(() async {
      await Connection.instance.disconnectAll();
      await agent.server.close(force: true);
    });
    Settings.instance.saveDevice(
      Device(
        id: 'timeline',
        host: '127.0.0.1',
        port: agent.port,
        token: 'timeline',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('timeline'));
    void report(String key) => agent.socket!.add([
      0x16,
      3,
      ...utf8.encode(
        jsonEncode({
          'title': 'Test video',
          'app': 'Firefox',
          'positionMs': 15000,
          'durationMs': 90000,
          'canSeek': true,
          'seekKey': key,
          'playing': false,
        }),
      ),
    ]);
    report('1234567890abcdef');
    await tester.runAsync(settle);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: TouchPad(enabled: true),
          ),
        ),
      ),
    );
    expect(find.text('0:15'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    agent.received.clear();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    for (final (button, usage) in [
      ('mediaPrevious', 182),
      ('mediaPlayPause', 205),
      ('mediaNext', 181),
    ]) {
      agent.received.clear();
      await tester.tap(find.byKey(Key(button)));
      await tester.runAsync(settle);
      expect(agent.received, ['1,128,$usage', '2,128,$usage']);
    }
    agent.received.clear();
    for (final (button, expected) in [
      ('mediaForward', 25000000),
      ('mediaBackward', 15000000),
    ]) {
      await tester.tap(find.byKey(Key(button)));
      await tester.runAsync(settle);
      final command = Uint8List.fromList(
        agent.received.last.split(',').map(int.parse).toList(),
      );
      expect(command[0], 7);
      expect(ByteData.sublistView(command).getUint64(9, Endian.big), expected);
    }
    agent.received.clear();
    final rect = tester.getRect(find.byKey(const Key('mediaSeekBar')));
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * .35, rect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      agent.received,
      isEmpty,
      reason: 'holding the timeline must not click the computer',
    );
    await gesture.moveTo(Offset(rect.right - 30, rect.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.runAsync(settle);
    expect(
      agent.received.length,
      1,
      reason: 'seeking must never click or move the pointer',
    );
    final bytes = agent.received.single.split(',').map(int.parse).toList();
    expect(bytes.length, 17);
    expect(bytes.take(9).toList(), [
      7,
      0x12,
      0x34,
      0x56,
      0x78,
      0x90,
      0xab,
      0xcd,
      0xef,
    ]);
    final positionUs = ByteData.sublistView(Uint8List.fromList(bytes))
        .getUint64(9, Endian.big);
    expect(positionUs, greaterThan(45000000));
    expect(positionUs, lessThanOrEqualTo(90000000));
    agent.received.clear();
    final staleDrag = await tester.startGesture(
      Offset(rect.left + rect.width * .35, rect.center.dy),
    );
    await staleDrag.moveTo(Offset(rect.right - 30, rect.center.dy));
    report('0000000000000001');
    await tester.runAsync(settle);
    await tester.pump();
    await staleDrag.up();
    await tester.runAsync(settle);
    expect(
      agent.received,
      isEmpty,
      reason: 'track change cancels an in-progress seek',
    );
    Connection.instance.seekMedia('timeline', '1234567890abcdef', 50000);
    await tester.runAsync(settle);
    expect(
      agent.received,
      isEmpty,
      reason: 'stale track seeks must be dropped',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 340,
              height: 150,
              child: TouchPad(enabled: true, compact: true),
            ),
          ),
        ),
      ),
    );
    final timeline = tester.getRect(find.byKey(const Key('mediaTimeline')));
    expect(timeline.top, 0);
    expect(timeline.bottom, lessThanOrEqualTo(56));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
