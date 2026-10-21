import 'dart:typed_data';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

class FakeMic implements MicSource {
  bool allowed = true, running = false;
  int starts = 0, stops = 0;
  void Function(Uint8List)? onData;

  @override
  Future<bool> start(void Function(Uint8List) cb) async {
    starts++;
    if (!allowed) return false;
    running = true;
    onData = cb;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  /// 20 ms of "speech" at the given amplitude.
  void speak([int amp = 6000]) {
    final b = ByteData(640);
    for (var i = 0; i < 320; i++) {
      b.setInt16(i * 2, i.isEven ? amp : -amp, Endian.little);
    }
    onData?.call(b.buffer.asUint8List());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAgent agent;
  late FakeMic mic;
  final v = VoiceController.instance;
  final c = Connection.instance;

  Future<void> pause([int ms = 400]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// Hold, speak a little, let go; waits for the answer and what comes of it.
  Future<void> say({required bool command}) async {
    await v.begin(asCommand: command);
    mic.speak();
    mic.speak();
    await v.end();
    await pause(500);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.load();
    agent = await FakeAgent.start('tok');
    Settings.instance.saveDevice(
      Device(
        id: 'vo',
        name: 'PC',
        host: '127.0.0.1',
        port: agent.port,
        token: 'tok',
      ),
    );
    await c.switchTo('vo');
    await pause(300);
    mic = FakeMic();
    v.mic = mic;
    v.reset();
    v.attach();
  });

  tearDown(() async {
    v.detach();
    await c.disconnectAll();
    await agent.server.close(force: true);
  });

  List<String> keys() => [
    for (final m in agent.received)
      if (m.startsWith('1,') || m.startsWith('2,')) m,
  ];

  test('dictation: the audio is sent in frames a Bluetooth link can carry, the text is typed', () async {
    agent.voiceText = 'hi';
    await v.begin(asCommand: false);
    expect(v.phase, VoicePhase.listening);
    mic.speak();
    mic.speak();
    await pause(200);
    expect(agent.voiceModes, [0]);
    expect(agent.voiceAudioBytes, 1280);
    await v.end();
    expect(mic.running, isFalse);
    await pause(500);
    expect(v.phase, VoicePhase.idle);
    expect(keys(), [
      '1,0,11',
      '2,0,11',
      '1,0,12',
      '2,0,12',
      '1,0,44',
      '2,0,44',
    ], reason: 'h i space');
    expect(v.history.first.kind, 'typed');
  });

  test('settings: no space, Enter after', () async {
    Settings.instance.update(() {
      Settings.instance.voiceSpace = false;
      Settings.instance.voiceEnter = true;
    });
    agent.voiceText = 'hi';
    await say(command: false);
    expect(keys(), [
      '1,0,11',
      '2,0,11',
      '1,0,12',
      '2,0,12',
      '1,0,40',
      '2,0,40',
    ]);
  });

  test(
    'a command is matched on the phone and run: copy, scroll, repeat',
    () async {
      agent.voiceText = 'Copy.';
      await say(command: true);
      expect(agent.voiceModes, [1]);
      expect(keys(), ['1,0,224', '1,0,6', '2,0,6', '2,0,224']);
      expect(v.history.first.kind, 'ran');

      agent.received.clear();
      agent.voiceText = 'press enter twice';
      await say(command: true);
      expect(keys(), ['1,0,40', '2,0,40', '1,0,40', '2,0,40']);

      agent.received.clear();
      agent.voiceText = 'scroll down a bit';
      await say(command: true);
      expect(
        agent.received.single,
        '5,0,0,255,252',
        reason: 'one scroll frame, 4 notches down',
      );
    },
  );

  test(
    'touchpad and round-menu options by voice: the right frames go out',
    () async {
      Future<List<String>> run(String phrase) async {
        agent.received.clear();
        agent.voiceText = phrase;
        await say(command: true);
        await pause(200);
        return List.of(agent.received);
      }

      expect(await run('scroll left'), [
        '5,255,252,0,0',
      ], reason: 'wheel sideways');
      expect(await run('middle click'), ['4,2,1', '4,2,0']);
      expect(await run('next workspace'), [
        '1,0,224',
        '1,0,226',
        '1,0,79',
        '2,0,79',
        '2,0,226',
        '2,0,224',
      ], reason: 'Ctrl+Alt+Right');
      expect(await run('pause'), [
        '1,128,205',
        '2,128,205',
      ], reason: 'consumer play/pause');
      expect(await run('take a screenshot'), [
        '1,0,70',
        '2,0,70',
      ], reason: 'Print Screen');
      expect(await run('switch windows'), [
        '1,0,226',
        '1,0,43',
        '2,0,43',
        '2,0,226',
      ], reason: 'Alt+Tab');
      expect(await run('terminal paste'), [
        '1,0,224',
        '1,0,225',
        '1,0,25',
        '2,0,25',
        '2,0,225',
        '2,0,224',
      ]);
      expect(await run('zoom in'), [
        '1,0,224',
        '5,0,0,0,2',
        '2,0,224',
      ], reason: 'Ctrl + wheel');
      expect(await run('start dragging'), ['4,0,1']);
      expect(await run('drop'), ['4,0,0']);
      final moved = await run('move the cursor left');
      expect(moved.single, '3,255,136,0,0', reason: '120 px to the left');
    },
  );

  test('a custom key of the round menu is spoken by its name', () async {
    Settings.instance.update(() {
      Settings.instance.editCustom = '[{"id":"custom_1","label":"Reopen tab","mods":3,"key":23,"repeats":false}]';
    });
    agent.voiceText = 'Reopen the tab.';
    await say(command: true);
    expect(keys(), [
      '1,0,224',
      '1,0,225',
      '1,0,23',
      '2,0,23',
      '2,0,225',
      '2,0,224',
    ], reason: 'Ctrl+Shift+T');
    expect(v.history.first.text, contains('Reopen tab'));
  });

  test('locking the screen asks first', () async {
    agent.voiceText = 'lock the screen';
    await say(command: true);
    expect(v.pending?.label, 'Lock screen');
    expect(agent.received, isEmpty);
    v.confirm();
    await pause(300);
    expect(agent.received, ['1,129,158', '2,129,158']);
  });

  test(
    'closing a window asks first; "Run" does it, "Cancel" does not',
    () async {
      agent.voiceText = 'Please close this window.';
      await say(command: true);
      expect(keys(), isEmpty);
      expect(v.pending?.label, 'Close application');
      expect(v.status, contains('Run'));
      v.confirm();
      await pause(300);
      expect(keys(), [
        '1,0,226',
        '1,0,61',
        '2,0,61',
        '2,0,226',
      ], reason: 'Alt+F4');
      expect(v.pending, isNull);

      agent.received.clear();
      await say(command: true);
      expect(v.pending, isNotNull);
      v.dismiss();
      await pause(200);
      expect(keys(), isEmpty);

      // With the question switched off it just closes.
      Settings.instance.update(
        () => Settings.instance.voiceConfirmRisky = false,
      );
      await say(command: true);
      await pause(200);
      expect(keys(), ['1,0,226', '1,0,61', '2,0,61', '2,0,226']);
    },
  );

  test('a phrase the list does not know is guessed by the computer, and only run after a yes', () async {
    Settings.instance.update(() => Settings.instance.voiceAi = true);
    agent.voiceText = 'shut the tab down';
    agent.voiceIntent = '{"t":"intent","calls":[{"name":"close_tab","arguments":{}}],"confidence":0.7}';
    await say(command: true);
    expect(agent.received, ['intent:shut the tab down']);
    expect(keys(), isEmpty, reason: 'a guess is never run by itself');
    expect(v.pending?.label, 'Close tab');
    v.confirm();
    await pause(300);
    expect(keys(), [
      '1,0,224',
      '1,0,26',
      '2,0,26',
      '2,0,224',
    ], reason: 'Ctrl+W');
  });

  test(
    'an unknown phrase with no guess, and with guessing switched off',
    () async {
      Settings.instance.update(() => Settings.instance.voiceAi = true);
      agent.voiceText = 'tell me a joke';
      await say(command: true);
      expect(v.pending, isNull);
      expect(v.status, 'Not understood');

      agent.received.clear();
      Settings.instance.update(() => Settings.instance.voiceAi = false);
      await say(command: true);
      expect(
        agent.received,
        isEmpty,
        reason: 'nothing is asked of the computer',
      );
      expect(v.status, 'No such command');
    },
  );

  test('the engine is not installed on the computer: said at once, nothing is recorded on', () async {
    agent.voiceText = null;
    await v.begin(asCommand: false);
    await pause(400);
    expect(v.phase, VoicePhase.idle);
    expect(v.error, contains('not installed'));
    expect(mic.running, isFalse);
  });

  test('microphone refused, and no computer connected', () async {
    mic.allowed = false;
    await v.begin(asCommand: false);
    expect(v.phase, VoicePhase.idle);
    expect(v.error, contains('microphone'));

    await c.disconnectAll();
    await pause(200);
    await v.begin(asCommand: false);
    expect(v.error, 'Not connected to a computer');
    expect(mic.starts, 1, reason: 'the microphone was not even asked');
  });

  test(
    'a slow computer: the screen says it is still working, then gives up',
    () async {
      VoiceController.slowHintAfter = const Duration(milliseconds: 300);
      VoiceController.answerTimeout = const Duration(milliseconds: 900);
      addTearDown(() {
        VoiceController.slowHintAfter = const Duration(seconds: 10);
        VoiceController.answerTimeout = const Duration(seconds: 200);
      });
      agent.voiceText = 'hi';
      agent.voiceMute = true;
      await v.begin(asCommand: false);
      mic.speak();
      await v.end();
      expect(v.status, 'Recognising...');
      await pause(450);
      expect(v.status, contains('Still working'));
      await pause(700);
      expect(v.phase, VoicePhase.idle);
      expect(v.error, 'The computer did not answer');
    },
  );

  test(
    'speech that is not heard, and letting go before the microphone is ready',
    () async {
      agent.voiceText = '';
      await say(command: false);
      expect(v.status, "Didn't catch that");
      expect(keys(), isEmpty);

      agent.voiceText = 'hi';
      final started = v.begin(asCommand: false);
      await v.end(); // let go straight away
      await started;
      await pause(500);
      expect(v.phase, VoicePhase.idle);
      expect(mic.running, isFalse);
    },
  );

  test('cancel stops the microphone and tells the computer', () async {
    await v.begin(asCommand: false);
    await v.cancel();
    expect(v.phase, VoicePhase.idle);
    expect(mic.running, isFalse);
  });

  test('a long answer arrives in pieces', () async {
    final long = 'word ' * 120; // more than one 248-byte piece
    agent.voiceText = long.trim();
    Settings.instance.update(() => Settings.instance.voiceSpace = false);
    await v.begin(asCommand: false);
    mic.speak();
    await v.end();
    await pause(1500);
    expect(v.phase, VoicePhase.idle);
    expect(keys().length, greaterThan(1000));
  });
}
