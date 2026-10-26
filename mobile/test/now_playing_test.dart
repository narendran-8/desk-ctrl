import 'dart:convert';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

import 'package:deskctrl/edge_zones.dart';
import 'package:deskctrl/links.dart' show WifiLink;
import 'package:deskctrl/now_playing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metadata reassembles UTF-8 and resets incomplete messages', () {
    final link = WifiLink();
    Map<String, dynamic>? info;
    link.onMedia = (value) => info = value;
    final bytes = utf8.encode(
      jsonEncode({'title': 'தமிழ் 🎵', 'app': 'Firefox'}),
    );
    link.receiveMedia([0x16, 1, ...bytes.take(15)]);
    expect(info, isNull);
    link.receiveMedia([0x16, 2, ...bytes.skip(15)]);
    expect(info?['title'], 'தமிழ் 🎵');
    link.receiveMedia([0x16, 1, 123, 99]);
    link.receiveMedia([0x16, 3, ...utf8.encode('{}')]);
    expect(info, isEmpty);
    link.dispose();
  });
  test('invalid icons do not hide the title', () {
    final media = NowPlaying.fromJson({
      'title': 'Track',
      'icon': '!!bad base64!!',
    });
    expect(media.title, 'Track');
    expect(media.icon, isNull);
  });
  for (final size in [const Size(800, 320), const Size(340, 150)]) {
    testWidgets('long title scrolls below playback controls at $size', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: const EdgeZoneMarks(
                  media: NowPlaying(
                    title: 'A very long currently playing video title that must scroll across the full playback width even in landscape',
                    app: 'Firefox',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final rect = tester.getRect(find.byKey(const Key('nowPlayingBadge')));
      expect(rect.width, closeTo(size.width * .6, .01));
      expect(rect.center.dx, closeTo(size.width / 2, .01));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(
        rect.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byIcon(Icons.play_arrow)).bottom,
        ),
      );
      final before = tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byKey(const Key('nowPlayingBadge')),
                  matching: find.byType(Transform),
                )
                .last,
          )
          .transform
          .getTranslation()
          .x;
      await tester.pump(const Duration(seconds: 3));
      final after = tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byKey(const Key('nowPlayingBadge')),
                  matching: find.byType(Transform),
                )
                .last,
          )
          .transform
          .getTranslation()
          .x;
      expect(after, lessThan(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final size in [const Size(800, 320), const Size(340, 150)]) {
    testWidgets('short title and icon center together at $size', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: const EdgeZoneMarks(
                  media: NowPlaying(title: 'Song', app: 'Firefox'),
                ),
              ),
            ),
          ),
        ),
      );
      final content = tester.getRect(
        find.byKey(const Key('nowPlayingContent')),
      );
      expect(content.center.dx, closeTo(size.width / 2, .01));
      expect(content.width, lessThan(size.width * .6));
      expect(
        find.descendant(
          of: find.byKey(const Key('nowPlayingBadge')),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty metadata hides the badge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EdgeZoneMarks())),
    );
    expect(find.byKey(const Key('nowPlayingBadge')), findsNothing);
  });
  testWidgets(
    'live titles follow the selected computer and hide in phone mode',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      final first = (await tester.runAsync(() => FakeAgent.start('first')))!;
      final second = (await tester.runAsync(() => FakeAgent.start('second')))!;
      addTearDown(() async {
        await Connection.instance.disconnectAll();
        await first.server.close(force: true);
        await second.server.close(force: true);
      });
      for (final pair in [('first', first), ('second', second)]) {
        Settings.instance.saveDevice(
          Device(
            id: pair.$1,
            host: '127.0.0.1',
            port: pair.$2.port,
            token: pair.$1,
          ),
        );
        await tester.runAsync(() => Connection.instance.connectDevice(pair.$1));
      }
      await tester.runAsync(() => Connection.instance.switchTo('first'));
      void send(FakeAgent agent, String title, String app) {
        agent.socket!.add([
          0x16,
          3,
          ...utf8.encode(
            jsonEncode({'title': title, 'app': app, 'playing': true}),
          ),
        ]);
      }

      send(first, 'Video one', 'Firefox');
      send(second, 'Song two', 'VLC');
      await tester.runAsync(settle);
      expect(Connection.instance.active?.nowPlaying.title, 'Video one');
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TouchPad(enabled: true))),
      );
      expect(
        find.bySemanticsLabel(RegExp('Firefox: Video one')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pause), findsOneWidget);
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
      expect(
        tester.getRect(find.textContaining('Drag: move')).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('nowPlayingBadge'))).bottom,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => Connection.instance.switchTo('second'));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('VLC: Song two')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Firefox: Video one')), findsNothing);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TouchPad(enabled: true, phoneMedia: true)),
        ),
      );
      expect(find.byKey(const Key('nowPlayingBadge')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
}
