import 'dart:math' as math;

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/pad_screen.dart';
import 'package:deskctrl/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

const _accel = 'dev.fluttercommunity.plus/sensors/accelerometer';
const _method = 'dev.fluttercommunity.plus/sensors/method';

void main() {
  late FakeAgent agent;
  MockStreamHandlerEventSink? accel;
  var micros = 1000000;

  void installSensors(WidgetTester tester) {
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockStreamHandler(
      const EventChannel(_accel),
      MockStreamHandler.inline(
        onListen: (_, sink) {
          accel = sink;
        },
        onCancel: (_) {
          accel = null;
        },
      ),
    );
    m.setMockMethodCallHandler(const MethodChannel(_method), (_) async => null);
    addTearDown(() {
      m.setMockStreamHandler(const EventChannel(_accel), null);
      m.setMockMethodCallHandler(const MethodChannel(_method), null);
      accel = null;
    });
  }

  Future<void> setUpPad(WidgetTester tester, {bool motion = true}) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    Settings.instance.update(() => Settings.instance.padMotion = motion);
    tester.view.physicalSize = const Size(1640, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    installSensors(tester);
    agent = (await tester.runAsync(() => FakeAgent.start('tok')))!;
    Settings.instance.saveDevice(
      Device(
        id: 'motion',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await tester.runAsync(() => Connection.instance.switchTo('motion'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PadScreen())),
    );
    await tester.pump();
  }

  tearDown(() async {
    await Connection.instance.disconnectAll();
    await agent.server.close(force: true);
  });

  /// The phone held upright in portrait, then leaned to the right by [lean] radians and tilted
  /// back (top of the screen away) by [back], for [steps] readings 20 ms apart, then held there.
  /// Each call starts from the upright pose (the pad engages on the first readings).
  Future<void> tilt(
    WidgetTester tester, {
    double lean = 0,
    double back = 0,
    int steps = 10,
  }) async {
    void reading(double l, double b) {
      micros += 20000;
      accel?.success(<double>[
        9.8 * math.sin(l),
        9.8 * math.cos(b),
        9.8 * math.sin(b),
        micros.toDouble(),
      ]);
    }

    for (var i = 0; i < 8; i++) {
      reading(0, 0); // upright: the clutch takes this as the centre
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    agent.received.removeWhere(
      (f) => f.startsWith('3,'),
    ); // settling back to the centre
    for (var i = 0; i < steps; i++) {
      reading(lean, back);
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
  }

  /// Total cursor movement the computer received (frames `3, dx hi, dx lo, dy hi, dy lo`).
  ({int dx, int dy}) cursor() {
    var dx = 0, dy = 0;
    int i16(int hi, int lo) => ((hi << 8) | lo).toSigned(16);
    for (final f in agent.received) {
      final b = f.split(',').map(int.parse).toList();
      if (b.first == 3) {
        dx += i16(b[1], b[2]);
        dy += i16(b[3], b[4]);
      }
    }
    return (dx: dx, dy: dy);
  }

  Offset middle(WidgetTester tester) => tester.getCenter(find.byType(TouchPad));

  testWidgets(
    'hold a finger on the pad and turn the phone to the right: the cursor goes right',
    (tester) async {
      await setUpPad(tester);
      final g = await tester.startGesture(middle(tester));
      await tilt(tester, lean: 0.3); // clockwise seen from above
      final c = cursor();
      expect(c.dx, greaterThan(50), reason: 'leaned right: $c');
      expect(c.dy.abs(), lessThan(3));
      agent.received.clear();
      await tilt(tester, lean: -0.3); // and back to the left
      expect(cursor().dx, lessThan(-50));
      agent.received.clear();
      await tilt(tester, back: -0.3); // the top of the screen towards you
      expect(cursor().dy, greaterThan(50));
      agent.received.clear();
      await tilt(tester, back: 0.3);
      expect(cursor().dy, lessThan(-50));
      await g.up();
      await tester.pump();
    },
  );

  testWidgets(
    'without a finger on the pad the cursor stays put (the finger is the clutch)',
    (tester) async {
      await setUpPad(tester);
      await tilt(tester, lean: 0.3);
      expect(agent.received.where((f) => f.startsWith('3,')), isEmpty);
      final g = await tester.startGesture(middle(tester));
      await g.up(); // lifted again
      await tester.pump(const Duration(milliseconds: 400));
      agent.received.clear();
      await tilt(tester, lean: 0.3);
      expect(agent.received.where((f) => f.startsWith('3,')), isEmpty);
    },
  );

  testWidgets('with the setting off, motion does nothing', (tester) async {
    await setUpPad(tester, motion: false);
    final g = await tester.startGesture(middle(tester));
    await tilt(tester, lean: 0.3);
    expect(agent.received.where((f) => f.startsWith('3,')), isEmpty);
    expect(accel, isNull, reason: 'the sensor is not even running');
    await g.up();
  });

  testWidgets('the sensors start and stop with the setting', (tester) async {
    await setUpPad(tester, motion: false);
    expect(accel, isNull);
    Settings.instance.update(() => Settings.instance.padMotion = true);
    await tester.pump();
    expect(accel, isNotNull, reason: 'switched on');
    Settings.instance.update(() => Settings.instance.padMotion = false);
    await tester.pump();
    expect(
      accel,
      isNull,
      reason: 'switched off: the sensors stop (saves battery)',
    );
    Settings.instance.update(() => Settings.instance.padMotion = true);
    await tester.pump();
    Settings.instance.update(
      () => Settings.instance.padEnabled = false,
    ); // the pad itself is off
    await tester.pump();
    expect(accel, isNull);
  });

  testWidgets(
    'a finger on an edge strip, or two fingers, do not move the cursor by motion',
    (tester) async {
      await setUpPad(tester);
      final r = tester.getRect(find.byType(TouchPad));
      final edge = await tester.startGesture(
        Offset(r.left + 12, r.center.dy),
      ); // the volume strip
      await tilt(tester, lean: 0.3);
      expect(agent.received.where((f) => f.startsWith('3,')), isEmpty);
      await edge.up();
      await tester.pump();

      final a = await tester.startGesture(middle(tester));
      final b = await tester.startGesture(middle(tester) + const Offset(60, 0));
      await tilt(tester, lean: 0.3);
      expect(agent.received.where((f) => f.startsWith('3,')), isEmpty);
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets('speed and invert settings are used', (tester) async {
    await setUpPad(tester);
    final g = await tester.startGesture(middle(tester));
    await tilt(tester, lean: 0.3);
    final normal = cursor().dx;
    agent.received.clear();
    Settings.instance.update(() => Settings.instance.padMotionSpeed = 1800);
    await tilt(tester, lean: 0.3);
    expect(
      cursor().dx,
      closeTo(normal * 2, normal * 0.25),
      reason: 'twice the speed',
    );
    agent.received.clear();
    Settings.instance.update(() {
      Settings.instance.padMotionSpeed = 900;
      Settings.instance.padMotionInvert = true;
    });
    await tilt(tester, lean: 0.3);
    expect(cursor().dx, lessThan(-(normal * 0.75)), reason: 'inverted');
    await g.up();
  });

  testWidgets('a tap while the phone is moved by hand is not a click', (
    tester,
  ) async {
    await setUpPad(tester);
    final g = await tester.startGesture(middle(tester));
    await tilt(tester, lean: 0.3, steps: 3);
    await g.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    expect(
      agent.received.where((f) => f.startsWith('4,')),
      isEmpty,
      reason: 'no click',
    );
    // A plain tap still clicks.
    agent.received.clear();
    final t = await tester.startGesture(middle(tester));
    await tester.pump(const Duration(milliseconds: 40));
    await t.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    expect(agent.received, containsAll(['4,0,1', '4,0,0']));
  });

  group('"also without touching the screen"', () {
    testWidgets('the cursor follows the phone with no finger on the pad', (
      tester,
    ) async {
      await setUpPad(tester);
      Settings.instance.update(() => Settings.instance.padMotionAlways = true);
      await tilt(tester, lean: 0.3);
      expect(cursor().dx, greaterThan(50), reason: 'moved with no finger down');
      agent.received.clear();
      await tilt(tester, back: -0.3);
      expect(cursor().dy, greaterThan(50));
    });

    testWidgets('a finger moves it at the same time', (tester) async {
      await setUpPad(tester);
      Settings.instance.update(() => Settings.instance.padMotionAlways = true);
      await tilt(tester, lean: 0.3);
      final motionOnly = cursor().dx;
      agent.received.clear();

      // The same tilt again, with a finger resting on the pad and dragging to the right.
      final g = await tester.startGesture(middle(tester));
      await tilt(tester, lean: 0.3);
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(25, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      expect(
        cursor().dx,
        greaterThan(motionOnly + 50),
        reason: 'the finger adds to the motion',
      );
    });

    testWidgets(
      'it works with a finger on a side strip too, and two fingers can scroll',
      (tester) async {
        await setUpPad(tester);
        Settings.instance.update(
          () => Settings.instance.padMotionAlways = true,
        );
        final r = tester.getRect(find.byType(TouchPad));
        final edge = await tester.startGesture(
          Offset(r.left + 12, r.center.dy),
        );
        await tilt(tester, lean: 0.3);
        expect(
          cursor().dx,
          greaterThan(50),
          reason: 'motion is not tied to touching the pad',
        );
        await edge.up();
        await tester.pump();
      },
    );

    testWidgets(
      'off by default: without the option there is still no movement without a finger',
      (tester) async {
        await setUpPad(tester);
        expect(Settings.instance.padMotionAlways, isFalse);
        await tilt(tester, lean: 0.3);
        expect(agent.received.where((f) => f.startsWith('3,')), isEmpty);
      },
    );

    testWidgets('the pad being switched off stops it', (tester) async {
      await setUpPad(tester);
      Settings.instance.update(() {
        Settings.instance.padMotionAlways = true;
        Settings.instance.padEnabled = false;
      });
      await tester.pump();
      await tilt(tester, lean: 0.3);
      expect(agent.received.where((f) => f.startsWith('3,')), isEmpty);
    });
  });
}
