import 'dart:io';

import 'package:deskctrl/connection.dart';
import 'package:deskctrl/edit_menu.dart';
import 'package:deskctrl/settings.dart';
import 'package:deskctrl/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent.dart';

void main() {
  group('phrases', () {
    test('normalisation drops punctuation and filler words', () {
      expect(normalizePhrase('Please, close THIS window.'), 'close window');
      expect(normalizePhrase('Open a terminal'), 'open terminal');
      expect(normalizePhrase('  Scroll   down a bit! '), 'scroll down');
    });

    test('what people say finds the action', () {
      String? id(String t) => matchPhrase(t)?.id;
      expect(id('Copy.'), 'copy');
      expect(id('copy that'), 'copy');
      expect(id('Please paste that here.'), 'paste');
      expect(id('Open a terminal'), 'open_terminal');
      expect(id('close this window'), 'close_app');
      expect(id('Close the tab'), 'close_tab');
      expect(id('reload the page'), 'refresh');
      expect(id('Scroll down a bit.'), 'scroll_down');
      expect(id('turn the volume up'), 'volume_up');
      expect(id('turn the volume down'), 'volume_down');
      expect(id('right click'), 'right_click');
      expect(id('Undo that.'), 'undo');
      expect(id('press enter'), 'enter');
      expect(id('select everything'), 'select_all');
      expect(id('tell me a joke'), isNull);
      expect(id('What is the weather like today?'), isNull);
      expect(id(''), isNull);
    });

    test('a count: "three times", "twice"', () {
      expect(matchPhrase('press enter three times')?.times, 3);
      expect(matchPhrase('press enter three times')?.id, 'enter');
      expect(matchPhrase('scroll down 5 times')?.times, 5);
      expect(matchPhrase('backspace twice')?.times, 2);
      expect(matchPhrase('delete 99 times')?.times, maxRepeat);
      expect(matchPhrase('copy')?.times, 1);
    });

    test('every phrase belongs to an action that can run', () {
      for (final id in voicePhrases.keys) {
        expect(commandFor(id), isNotNull, reason: id);
      }
      expect(commandFor('nope'), isNull);
    });

    test('closing a window and locking the screen are the risky commands', () {
      for (final id in voicePhrases.keys) {
        expect(
          commandFor(id)!.risky,
          id == 'close_app' || id == 'lock_screen',
          reason: id,
        );
      }
    });

    test(
      'every option of the round menu and of the touchpad can be spoken',
      () {
        for (final id in editCatalog.keys) {
          expect(
            voicePhrases.containsKey(id),
            isTrue,
            reason: 'round menu: $id',
          );
        }
        String? id(String t) => matchPhrase(t)?.id;
        expect(id('terminal paste'), 'terminal_paste');
        expect(id('middle click'), 'middle_click');
        expect(id('start dragging'), 'drag_start');
        expect(id('drop'), 'drag_end');
        expect(id('scroll to the top'), 'scroll_top');
        expect(id('scroll right'), 'scroll_right');
        expect(id('zoom in'), 'zoom_in');
        expect(id('next workspace'), 'workspace_right');
        expect(id('show overview'), 'overview');
        expect(id('take a screenshot'), 'screenshot');
        expect(id('brighter'), 'brightness_up');
        expect(id('pause'), 'play_pause');
        expect(id('next song'), 'next_track');
        expect(id('rewind'), 'seek_back');
        expect(id('switch windows'), 'next_window');
        expect(id('previous tab'), 'prev_tab');
        expect(id('move the cursor left'), 'move_left');
        expect(id('press down'), 'arrow_down');
        expect(id('lock the screen'), 'lock_screen');
      },
    );

    test(
      'the computer\'s helper knows exactly the actions the phone can run',
      () {
        final py = File('../agent/voice/voice_helper.py').readAsStringSync();
        final block = py.substring(
          py.indexOf('ACTIONS = {'),
          py.indexOf('TOOLS = ['),
        );
        final helper = {
          for (final m in RegExp(r'"([a-z_]+)":\s*"').allMatches(block))
            m.group(1)!,
        };
        expect(helper, voicePhrases.keys.toSet());
        for (final id in helper) {
          expect(commandFor(id), isNotNull, reason: id);
        }
        expect(
          editCatalog.keys.toSet().containsAll(
            helper.where(editCatalog.containsKey),
          ),
          isTrue,
        );
      },
    );
  });

  group('typing', () {
    test('characters of a US keyboard', () {
      expect(keyForChar('a'), (0x04, false));
      expect(keyForChar('Z'), (0x1D, true));
      expect(keyForChar('1'), (0x1E, false));
      expect(keyForChar('0'), (0x27, false));
      expect(keyForChar('!'), (0x1E, true));
      expect(keyForChar(' '), (0x2C, false));
      expect(keyForChar('?'), (0x38, true));
      expect(keyForChar('\n'), (0x28, false));
      expect(keyForChar('é'), isNull);
      expect(keyForChar('ab'), isNull);
    });

    test('text goes out as key presses, Shift around capitals; what cannot be typed is counted', () async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.load();
      final agent = await FakeAgent.start('tok');
      Settings.instance.saveDevice(
        Device(
          id: 'ty',
          name: 'PC',
          host: '127.0.0.1',
          port: agent.port,
          token: 'tok',
        ),
      );
      final c = Connection.instance;
      await c.switchTo('ty');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final skipped = await typeText('Hi, é5');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(skipped, 1);
      expect(agent.received, [
        '1,0,225', '1,0,11', '2,0,11', '2,0,225', // H
        '1,0,12', '2,0,12', // i
        '1,0,54', '2,0,54', // ,
        '1,0,44', '2,0,44', // space
        '1,0,34', '2,0,34', // 5
      ]);
      await c.disconnectAll();
      await agent.server.close(force: true);
    });
  });
}
