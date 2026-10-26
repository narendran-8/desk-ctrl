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
  test('same video preserves duration through null/zero reports without borrowing across videos', () {
    final json = <String, dynamic>{
      'title': 'Video',
      'app': 'Firefox',
      'player': 'org.mpris.firefox',
      'trackId': '/firefox',
      'mediaUrl': 'video1',
      'positionMs': 90000,
      'durationMs': 360000,
      'canSeek': true,
      'seekKey': '1234567890abcdef',
    };
    final original = NowPlaying.fromJson(json);
    final gap = NowPlaying.fromJson({
      ...json,
      'durationMs': null,
      'positionMs': null,
      'seekKey': '0000000000000001',
    }, previous: original);
    expect(gap.durationMs, 360000);
    expect(gap.positionMs, 90000);
    expect(gap.seekable, isTrue);
    final zero = NowPlaying.fromJson({...json, 'durationMs': 0}, previous: gap);
    expect(zero.durationMs, 360000);
    final next = NowPlaying.fromJson({
      ...json,
      'mediaUrl': 'video2',
      'durationMs': 0,
    }, previous: zero);
    expect(next.durationMs, 0);
    expect(next.seekable, isFalse);
    expect(NowPlaying.fromJson({}, previous: original).hasTimeline, isFalse);
  });
  testWidgets(
    'seek preview and total survive missing metadata and legacy key changes',
    (tester) async {
      final sent = <int>[];
      final json = <String, dynamic>{
        'title': 'Video',
        'app': 'Firefox',
        'player': 'org.mpris.firefox',
        'trackId': '/firefox',
        'mediaUrl': 'video1',
        'positionMs': 20000,
        'durationMs': 360000,
        'canSeek': true,
        'seekKey': '1234567890abcdef',
      };
      var media = NowPlaying.fromJson(json);
      Widget view() => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: MediaTimeline(media: media, onSeek: (_, p) => sent.add(p)),
          ),
        ),
      );
      await tester.pumpWidget(view());
      // A real pointer drag to a random position; the source temporarily drops its timing.
      var rect = tester.getRect(find.byKey(const Key('mediaSeekBar')));
      final drag = await tester.startGesture(
        Offset(rect.left + 15, rect.center.dy),
      );
      await drag.moveTo(Offset(rect.left + rect.width * .4, rect.center.dy));
      media = NowPlaying.fromJson({
        ...json,
        'durationMs': null,
        'positionMs': null,
        'seekKey': '0000000000000001',
      }, previous: media);
      await tester.pumpWidget(view());
      await drag.up();
      await tester.pump();
      expect(sent.length, 1);
      expect(find.text('6:00'), findsOneWidget);
      expect(
        tester.widget<Slider>(find.byKey(const Key('mediaSeekBar'))).max,
        360000,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(
        tester.widget<Slider>(find.byKey(const Key('mediaSeekBar'))).value,
        closeTo(sent.single.toDouble(), 1),
      );
      media = NowPlaying.fromJson({
        ...json,
        'positionMs': sent.single,
        'durationMs': 0,
        'seekKey': '0000000000000001',
      }, previous: media);
      await tester.pumpWidget(view());
      expect(find.text('6:00'), findsOneWidget);
      expect(
        tester.widget<Slider>(find.byKey(const Key('mediaSeekBar'))).value,
        closeTo(sent.single.toDouble(), 1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('seek clock advances beyond five seconds through stale zero and old-position reports', () {
    final at = DateTime(2026);
    final json = <String, dynamic>{
      'title': 'Video',
      'app': 'Firefox',
      'player': 'org.mpris.firefox',
      'trackId': '/firefox',
      'mediaUrl': 'video1',
      'positionMs': 20000,
      'durationMs': 360000,
      'playing': true,
      'canSeek': true,
      'seekKey': '1234567890abcdef',
    };
    var media = NowPlaying.fromJson(json, now: at).afterSeek(150000, now: at);
    for (var second = 1; second <= 15; second++) {
      media = NowPlaying.fromJson(
        {...json, 'positionMs': second.isEven ? second * 1000 : 0},
        previous: media,
        now: at.add(Duration(seconds: second)),
      );
      expect(media.positionMs, 150000 + second * 1000);
      expect(media.positionEstimated, isTrue);
    }
    media = NowPlaying.fromJson(
      {...json, 'positionMs': 166000},
      previous: media,
      now: at.add(const Duration(seconds: 16)),
    );
    expect(media.positionMs, 166000);
    expect(media.positionEstimated, isFalse);
    // A later valid seek to zero is authoritative once normal feedback resumed.
    media = NowPlaying.fromJson(
      {...json, 'positionMs': 0},
      previous: media,
      now: at.add(const Duration(seconds: 17)),
    );
    expect(media.positionMs, 0);
  });
  test('unconfirmed seek respects pause, repeat seeks and video changes', () {
    final at = DateTime(2026);
    final json = <String, dynamic>{
      'title': 'Video',
      'app': 'Firefox',
      'player': 'org.mpris.firefox',
      'trackId': '/firefox',
      'mediaUrl': 'video1',
      'positionMs': 20000,
      'durationMs': 360000,
      'playing': false,
      'canSeek': true,
      'seekKey': '1234567890abcdef',
    };
    var media = NowPlaying.fromJson(json, now: at).afterSeek(150000, now: at);
    for (var second = 1; second <= 8; second++) {
      media = NowPlaying.fromJson(
        {...json, 'positionMs': 20000},
        previous: media,
        now: at.add(Duration(seconds: second)),
      );
    }
    expect(media.positionMs, 150000);
    media = media.afterSeek(240000, now: at.add(const Duration(seconds: 8)));
    media = NowPlaying.fromJson(
      {...json, 'positionMs': 0},
      previous: media,
      now: at.add(const Duration(seconds: 9)),
    );
    expect(media.positionMs, 240000);
    final next = NowPlaying.fromJson(
      {...json, 'mediaUrl': 'video2', 'positionMs': 0},
      previous: media,
      now: at.add(const Duration(seconds: 10)),
    );
    expect(next.positionMs, 0);
    expect(next.positionEstimated, isFalse);
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
      expect(find.text('--:--'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    },
  );
  testWidgets(
    'seek holds accumulate, stop on release, cancel and track change',
    (tester) async {
      final seeks = <int>[];
      Widget view({String track = '1234567890abcdef', bool enabled = true}) =>
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: MediaTimeline(
                  media: NowPlaying(
                    positionMs: 40000,
                    durationMs: 180000,
                    canSeek: enabled,
                    seekKey: track,
                  ),
                  onSeek: (_, position) => seeks.add(position),
                ),
              ),
            ),
          );
      await tester.pumpWidget(view());
      final forward = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('mediaForward'))),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      expect(seeks, [50000, 60000, 70000]);
      await forward.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(seeks.length, 3);
      final backward = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('mediaBackward'))),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(seeks.sublist(3), [60000, 50000]);
      await backward.cancel();
      await tester.pump(const Duration(milliseconds: 300));
      expect(seeks.length, 5);
      final changed = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('mediaForward'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final count = seeks.length;
      await tester.pumpWidget(view(track: '0000000000000001'));
      await tester.pump(const Duration(milliseconds: 700));
      await changed.up();
      expect(seeks.length, count);
      final disabled = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('mediaForward'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final beforeDisable = seeks.length;
      await tester.pumpWidget(view(track: '0000000000000001', enabled: false));
      await tester.pump(const Duration(milliseconds: 700));
      await disabled.up();
      expect(seeks.length, beforeDisable);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'same seek button can be held repeatedly after rebuild and finger drift',
    (tester) async {
      final seeks = <int>[];
      Widget view(int position) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MediaTimeline(
              media: NowPlaying(
                positionMs: position,
                durationMs: 600000,
                canSeek: true,
                seekKey: '1234567890abcdef',
              ),
              onSeek: (_, p) => seeks.add(p),
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(40000));
      for (final name in [
        'mediaForward',
        'mediaForward',
        'mediaBackward',
        'mediaBackward',
      ]) {
        final before = seeks.length;
        final center = tester.getCenter(find.byKey(Key(name)));
        final hold = await tester.startGesture(center);
        await tester.pump(const Duration(milliseconds: 600));
        // Small natural finger drift must not cancel a hold on a narrow button.
        await hold.moveTo(center + const Offset(16, 0));
        await tester.pumpWidget(view(seeks.last));
        await tester.pump(const Duration(milliseconds: 500));
        expect(seeks.length, before + 3);
        final values = seeks.sublist(before);
        expect(values[1] - values[0], name == 'mediaForward' ? 10000 : -10000);
        expect(values[2] - values[1], name == 'mediaForward' ? 10000 : -10000);
        await hold.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(seeks.length, before + 3);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Firefox unknown duration allows consecutive seek holds but not timeline drag',
    (tester) async {
      final seeks = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: MediaTimeline(
                media: const NowPlaying(
                  title: 'Firefox video',
                  positionMs: 20000,
                  canSeek: true,
                  seekKey: '1234567890abcdef',
                ),
                onSeek: (_, p) => seeks.add(p),
              ),
            ),
          ),
        ),
      );
      expect(find.text('--:--'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      for (final key in [
        'mediaForward',
        'mediaForward',
        'mediaBackward',
        'mediaBackward',
      ]) {
        final before = seeks.length;
        final hold = await tester.startGesture(
          tester.getCenter(find.byKey(Key(key))),
        );
        await tester.pump(const Duration(milliseconds: 800));
        await hold.up();
        await tester.pump(const Duration(milliseconds: 100));
        expect(seeks.length, before + 2);
      }
      expect(seeks, [30000, 40000, 50000, 60000, 50000, 40000, 30000, 20000]);
      await tester.pumpWidget(const SizedBox());
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
    final rect = tester.getRect(find.byKey(const Key('mediaSeekBar')));
    final gesture = await tester.startGesture(
      Offset(rect.left + 12, rect.center.dy),
    );
    await gesture.moveTo(Offset(rect.right - 12, rect.center.dy));
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
    await tester.tap(find.byKey(const Key('mediaForward')));
    await tester.runAsync(settle);
    expect(agent.received.single.startsWith('7,'), isTrue);
    agent.received.clear();
    await tester.tap(find.byKey(const Key('mediaPlayPause')));
    await tester.runAsync(settle);
    expect(agent.received, ['1,128,205', '2,128,205']);
    agent.received.clear();
    final staleDrag = await tester.startGesture(
      Offset(rect.left + 12, rect.center.dy),
    );
    await staleDrag.moveTo(Offset(rect.right - 12, rect.center.dy));
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
    expect(timeline.bottom, 40);
    expect(
      tester.getCenter(find.byKey(const Key("mediaElapsed"))).dy,
      tester.getCenter(find.byKey(const Key("mediaDuration"))).dy,
    );
    final order = [
      'mediaPrevious',
      'mediaBackward',
      'mediaElapsed',
      'mediaPlayPause',
      'mediaDuration',
      'mediaForward',
      'mediaNext',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        tester.getCenter(find.byKey(Key(order[i - 1]))).dx,
        lessThan(tester.getCenter(find.byKey(Key(order[i]))).dx),
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
