import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'connection.dart';
import 'settings.dart';
import 'voice_commands.dart';

/// Where the microphone audio comes from: 16 kHz, mono, 16-bit little-endian samples.
abstract class MicSource {
  /// Starts recording; false when the microphone cannot be used (permission refused ...).
  Future<bool> start(void Function(Uint8List pcm) onData);
  Future<void> stop();
}

/// The phone's microphone through MainActivity.kt / Mic.kt.
class PlatformMic implements MicSource {
  static const _m = MethodChannel('deskctrl/mic');
  static const _audio = EventChannel('deskctrl/mic/audio');
  StreamSubscription<dynamic>? _sub;

  @override
  Future<bool> start(void Function(Uint8List pcm) onData) async {
    try {
      _sub = _audio.receiveBroadcastStream().listen(
        (b) => onData(b as Uint8List),
        onError: (_) {},
      );
      return await _m.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      await stop();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _m.invokeMethod('stop');
    } catch (_) {}
  }
}

enum VoicePhase { idle, starting, listening, working }

/// One line of what happened, newest first on the screen.
class VoiceEntry {
  final String text;

  /// typed: dictated text; ran: a command was run; ask: waiting for a yes; info: anything else.
  final String kind;
  const VoiceEntry(this.text, this.kind);
}

/// The voice screen's brain. It records the microphone, sends the audio to the computer (which
/// turns it into text, see agent/src/voice.rs), and then either types the text (dictation) or
/// works out which action it means (commands: the phrase list first, then a guess from Needle
/// that is only run after a "yes").
class VoiceController extends ChangeNotifier {
  VoiceController._();
  static final VoiceController instance = VoiceController._();

  /// Replaced in tests.
  MicSource mic = PlatformMic();

  // Phone -> agent frame: 0x06, then 1 begin [mode], 2 audio, 3 end, 4 cancel, 5 intent request.
  static const _frame = 0x06;
  static const _begin = 1, _audio = 2, _end = 3, _cancel = 4, _intent = 5;
  static const _chunk =
      250; // fits a Bluetooth frame together with the two header bytes

  VoicePhase phase = VoicePhase.idle;
  bool command = false;
  String status = '';
  String? error;
  final List<VoiceEntry> history = [];
  VoiceCommand? pending;

  /// 0..1, how loud the last piece of audio was (for the level bar).
  final level = ValueNotifier<double>(0);

  final List<int> _answer = [];
  String _heardText = '';
  bool _askingIntent = false;
  bool _stopRequested = false;
  Timer? _timeout;

  /// How long to wait for the computer's answer (a slow computer loads the model first).
  static Duration answerTimeout = const Duration(seconds: 200);

  /// After this long without an answer the screen says it is still working (a slow computer, or
  /// the models being loaded for the first time).
  static Duration slowHintAfter = const Duration(seconds: 10);
  Timer? _slowHint;

  bool get busy => phase != VoicePhase.idle;

  /// A clean start (tests; the controller is a singleton).
  @visibleForTesting
  void reset() {
    _timeout?.cancel();
    _slowHint?.cancel();
    phase = VoicePhase.idle;
    status = '';
    error = null;
    pending = null;
    history.clear();
    _answer.clear();
  }

  void attach() {
    Connection.instance.onVoice = onFrame;
  }

  void detach() {
    if (Connection.instance.onVoice == onFrame)
      Connection.instance.onVoice = null;
    cancel();
  }

  void _set(VoicePhase p, [String s = '']) {
    phase = p;
    status = s;
    notifyListeners();
  }

  void _note(String text, String kind) {
    history.insert(0, VoiceEntry(text, kind));
    if (history.length > 8) history.removeLast();
  }

  /// The button went down (or was tapped): start listening.
  Future<void> begin({required bool asCommand}) async {
    if (phase != VoicePhase.idle) return;
    error = null;
    if (!Connection.instance.anyActive) {
      error = 'Not connected to a computer';
      notifyListeners();
      return;
    }
    pending = null;
    command = asCommand;
    _stopRequested = false;
    _set(VoicePhase.starting);
    final ok = await mic.start(_onAudio);
    if (!ok) {
      error =
          'The microphone is not available (allow it in the phone settings)';
      _set(VoicePhase.idle);
      return;
    }
    if (Settings.instance.haptic) HapticFeedback.selectionClick();
    Connection.instance.sendVoice([_frame, _begin, asCommand ? 1 : 0]);
    _set(
      VoicePhase.listening,
      asCommand ? 'Listening for a command...' : 'Listening...',
    );
    if (_stopRequested) await end(); // let go before the microphone was ready
  }

  void _onAudio(Uint8List pcm) {
    if (phase != VoicePhase.listening) return;
    var peak = 0;
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      peak = math.max(peak, ((pcm[i + 1] << 8) | pcm[i]).toSigned(16).abs());
    }
    level.value = math.min(1.0, peak / 12000);
    for (var i = 0; i < pcm.length; i += _chunk) {
      Connection.instance.sendVoice([
        _frame,
        _audio,
        ...pcm.sublist(i, math.min(i + _chunk, pcm.length)),
      ]);
    }
  }

  /// The button was let go (or tapped again): send it off for recognition.
  Future<void> end() async {
    if (phase == VoicePhase.starting) {
      _stopRequested = true;
      return;
    }
    if (phase != VoicePhase.listening) return;
    await mic.stop();
    level.value = 0;
    Connection.instance.sendVoice([_frame, _end]);
    _answer.clear();
    _askingIntent = false;
    _set(VoicePhase.working, 'Recognising...');
    _armTimeout();
  }

  Future<void> cancel() async {
    _timeout?.cancel();
    if (phase == VoicePhase.listening || phase == VoicePhase.starting) {
      await mic.stop();
      Connection.instance.sendVoice([_frame, _cancel]);
    }
    level.value = 0;
    if (phase != VoicePhase.idle) _set(VoicePhase.idle);
  }

  void _armTimeout() {
    _timeout?.cancel();
    _slowHint?.cancel();
    _slowHint = Timer(slowHintAfter, () {
      if (phase == VoicePhase.working) {
        status = 'Still working - the computer is slow or loading the model...';
        notifyListeners();
      }
    });
    _timeout = Timer(answerTimeout, () {
      if (phase == VoicePhase.working) {
        error = 'The computer did not answer';
        _set(VoicePhase.idle);
      }
    });
  }

  /// A piece of the computer's answer: `[0x15, last, ...json]`.
  void onFrame(Uint8List f) {
    if (f.length < 2) return;
    _answer.addAll(f.sublist(2));
    if (f[1] == 0) return;
    final bytes = List<int>.of(_answer);
    _answer.clear();
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    _handle(json);
  }

  Future<void> _handle(Map<String, dynamic> j) async {
    if (j['t'] == 'unavailable') {
      // Told right after the button went down: stop listening, nothing could be recognised.
      _timeout?.cancel();
      await cancel();
      error =
          j['msg'] as String? ??
          'The voice engine is not installed on the computer';
      notifyListeners();
      return;
    }
    if (phase != VoicePhase.working) return; // cancelled meanwhile
    _timeout?.cancel();
    _slowHint?.cancel();
    switch (j['t']) {
      case 'text':
        await _onText((j['text'] as String? ?? '').trim());
      case 'intent':
        _onIntent(j);
      default:
        error = j['msg'] as String? ?? 'Voice recognition failed';
        _set(VoicePhase.idle);
    }
  }

  Future<void> _onText(String text) async {
    _heardText = text;
    if (text.isEmpty) {
      _note("Didn't catch that", 'info');
      _set(VoicePhase.idle, "Didn't catch that");
      return;
    }
    if (!command) {
      await _dictate(text);
      return;
    }
    final m = matchPhrase(text);
    final cmd = m == null
        ? customKeyCommand(text)
        : commandFor(m.id, times: m.times);
    if (cmd != null) {
      _runOrAsk(cmd, text);
      return;
    }
    if (Settings.instance.voiceAi) {
      _askingIntent = true;
      Connection.instance.sendVoice([_frame, _intent, ...utf8.encode(text)]);
      _set(VoicePhase.working, 'Thinking about "$text"...');
      _armTimeout();
      return;
    }
    _note('"$text": no such command', 'info');
    _set(VoicePhase.idle, 'No such command');
  }

  Future<void> _dictate(String text) async {
    final s = Settings.instance;
    _set(VoicePhase.working, 'Typing...');
    final skipped = await typeText(s.voiceSpace ? '$text ' : text);
    if (s.voiceEnter) await typeText('\n');
    _note(text, 'typed');
    if (skipped > 0) _note('$skipped character(s) could not be typed', 'info');
    _set(VoicePhase.idle);
  }

  void _runOrAsk(VoiceCommand cmd, String heard) {
    if (cmd.risky && Settings.instance.voiceConfirmRisky) {
      pending = cmd;
      _note('"$heard": ${cmd.label}?', 'ask');
      _set(VoicePhase.idle, 'Run "${cmd.label}"?');
      return;
    }
    cmd.run();
    _note('"$heard": ${cmd.label}', 'ran');
    _set(VoicePhase.idle, cmd.label);
  }

  void _onIntent(Map<String, dynamic> j) {
    if (!_askingIntent) return;
    _askingIntent = false;
    final calls = (j['calls'] as List?) ?? const [];
    final name = calls.isEmpty ? null : (calls.first as Map)['name'] as String?;
    final cmd = name == null ? null : commandFor(name);
    if (cmd == null) {
      _note('"$_heardText": not understood', 'info');
      _set(VoicePhase.idle, 'Not understood');
      return;
    }
    // A guess: never run without a yes.
    pending = cmd;
    _note('"$_heardText": did you mean ${cmd.label}?', 'ask');
    _set(VoicePhase.idle, 'Did you mean "${cmd.label}"?');
  }

  /// "Run it" on the question.
  void confirm() {
    final c = pending;
    pending = null;
    if (c != null) {
      c.run();
      _note(c.label, 'ran');
      status = c.label;
    }
    notifyListeners();
  }

  void dismiss() {
    pending = null;
    status = '';
    notifyListeners();
  }
}
