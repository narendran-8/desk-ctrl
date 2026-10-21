import 'connection.dart';
import 'edit_menu.dart';

/// What a spoken phrase can do: a name to show, whether it needs a "yes" first, and the action.
class VoiceCommand {
  final String id;
  final String label;

  /// Closing a window or locking the screen can cost something: asked first (unless switched off in Settings).
  final bool risky;
  final void Function() run;
  const VoiceCommand(this.id, this.label, this.run, {this.risky = false});
}

/// Phrases for each action, as a person says them. They are compared after [normalizePhrase]
/// (lower case, no punctuation, no filler words), so "Please close this window." matches
/// "close window".
const voicePhrases = <String, List<String>>{
  'copy': ['copy', 'copy selection', 'copy text'],
  'cut': ['cut', 'cut selection', 'cut text'],
  'paste': ['paste', 'paste text', 'paste clipboard'],
  'undo': ['undo', 'undo last', 'undo change', 'undo last change'],
  'redo': ['redo', 'redo change'],
  'select_all': ['select all', 'select everything', 'select all text'],
  'find': ['find', 'search', 'find text', 'search page', 'open search'],
  'save': ['save', 'save file', 'save document'],
  'enter': [
    'enter',
    'press enter',
    'new line',
    'return',
    'press return',
    'next line',
  ],
  'backspace': ['backspace', 'press backspace'],
  'delete': ['delete', 'press delete'],
  'escape': ['escape', 'press escape', 'cancel'],
  'tab': ['tab', 'press tab'],
  'refresh': ['refresh', 'reload', 'refresh page', 'reload page'],
  'open_terminal': [
    'open terminal',
    'terminal',
    'launch terminal',
    'start terminal',
    'open console',
    'open command line',
  ],
  'close_app': [
    'close window',
    'close application',
    'close app',
    'close program',
    'quit application',
    'quit window',
  ],
  'new_tab': ['new tab', 'open tab', 'open new tab'],
  'close_tab': ['close tab', 'close current tab'],
  'page_up': ['page up'],
  'page_down': ['page down'],
  'home': ['home', 'start of line', 'go to start'],
  'end': ['end', 'end of line', 'go to end'],
  'scroll_up': ['scroll up', 'scroll upwards'],
  'scroll_down': ['scroll down', 'scroll downwards'],
  'volume_up': [
    'volume up',
    'louder',
    'increase volume',
    'raise volume',
    'turn volume up',
    'sound up',
  ],
  'volume_down': [
    'volume down',
    'quieter',
    'decrease volume',
    'lower volume',
    'turn volume down',
    'sound down',
  ],
  'mute': ['mute', 'unmute', 'mute sound', 'toggle mute'],
  'click': ['click', 'left click', 'click mouse'],
  'right_click': ['right click', 'context menu'],
  'double_click': ['double click'],
  // The rest of the round menu.
  'terminal_copy': ['terminal copy', 'copy in terminal', 'copy from terminal'],
  'terminal_paste': [
    'terminal paste',
    'paste in terminal',
    'paste into terminal',
  ],
  // The touchpad: buttons, drag, scrolling, zoom, three-finger gestures, edge strips.
  'middle_click': ['middle click', 'scroll click'],
  'drag_start': [
    'start drag',
    'start dragging',
    'hold click',
    'hold mouse',
    'press and hold',
    'drag',
  ],
  'drag_end': [
    'stop drag',
    'stop dragging',
    'drop',
    'release',
    'release click',
    'let go',
    'release mouse',
  ],
  'scroll_left': ['scroll left'],
  'scroll_right': ['scroll right'],
  'scroll_top': [
    'scroll to top',
    'top of page',
    'go to top',
    'scroll to the top',
  ],
  'scroll_bottom': [
    'scroll to bottom',
    'bottom of page',
    'go to bottom',
    'scroll to the bottom',
  ],
  'zoom_in': ['zoom in', 'zoom bigger', 'make bigger'],
  'zoom_out': ['zoom out', 'zoom smaller', 'make smaller'],
  'workspace_left': [
    'workspace left',
    'previous workspace',
    'desktop left',
    'switch workspace left',
  ],
  'workspace_right': [
    'workspace right',
    'next workspace',
    'desktop right',
    'switch workspace right',
  ],
  'overview': [
    'overview',
    'show overview',
    'show all windows',
    'activities',
    'open overview',
  ],
  'screenshot': [
    'screenshot',
    'take screenshot',
    'capture screen',
    'print screen',
  ],
  'brightness_up': [
    'brightness up',
    'increase brightness',
    'brighter',
    'raise brightness',
  ],
  'brightness_down': [
    'brightness down',
    'decrease brightness',
    'dimmer',
    'lower brightness',
  ],
  'play_pause': [
    'play',
    'pause',
    'play pause',
    'resume',
    'play music',
    'pause music',
    'play video',
    'pause video',
    'toggle playback',
  ],
  'next_track': ['next track', 'next song', 'skip track', 'skip song', 'skip'],
  'prev_track': ['previous track', 'previous song', 'last track', 'last song'],
  'seek_forward': ['forward', 'skip forward', 'seek forward', 'fast forward'],
  'seek_back': [
    'backward',
    'rewind',
    'seek back',
    'seek backward',
    'skip back',
  ],
  'next_window': ['next window', 'switch window', 'switch windows', 'alt tab'],
  'prev_window': ['previous window', 'window back'],
  'next_tab': ['next tab', 'tab right', 'switch tab'],
  'prev_tab': ['previous tab', 'tab left'],
  'move_left': [
    'move cursor left',
    'move mouse left',
    'cursor left',
    'mouse left',
  ],
  'move_right': [
    'move cursor right',
    'move mouse right',
    'cursor right',
    'mouse right',
  ],
  'move_up': ['move cursor up', 'move mouse up', 'cursor up', 'mouse up'],
  'move_down': [
    'move cursor down',
    'move mouse down',
    'cursor down',
    'mouse down',
  ],
  'arrow_left': ['arrow left', 'press left', 'left arrow'],
  'arrow_right': ['arrow right', 'press right', 'right arrow'],
  'arrow_up': ['arrow up', 'press up', 'up arrow'],
  'arrow_down': ['arrow down', 'press down', 'down arrow'],
  'space': ['space', 'press space', 'space bar'],
  'lock_screen': ['lock screen', 'lock computer', 'lock'],
};

const _filler = {
  'please',
  'kindly',
  'the',
  'a',
  'an',
  'this',
  'that',
  'it',
  'here',
  'now',
  'just',
  'me',
  'for',
  'bit',
  'little',
  'slightly',
  'ok',
  'okay',
  'hey',
  'then',
  'and',
  'can',
  'could',
  'you',
  'will',
  'would',
  'to',
  'go',
  'do',
};

/// Lower case, letters and digits only, filler words dropped: the form phrases are compared in.
String normalizePhrase(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9 ]+"), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty && !_filler.contains(w))
    .join(' ');

final _byPhrase = {
  for (final e in voicePhrases.entries)
    for (final p in e.value) normalizePhrase(p): e.key,
};

const _numbers = {
  'once': 1,
  'one': 1,
  'twice': 2,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
};

const maxRepeat = 10;

/// "press enter three times" -> (enter, 3). Null when no phrase matches.
({String id, int times})? matchPhrase(String text) {
  var words = normalizePhrase(text);
  var times = 1;
  final m = RegExp(r'^(.*?)\s*\b(\w+)\s+times?$').firstMatch(words);
  final n = m == null
      ? null
      : (_numbers[m.group(2)] ?? int.tryParse(m.group(2)!));
  if (m != null && n != null && n >= 1) {
    times = n.clamp(1, maxRepeat);
    words = m.group(1)!;
  } else if (words.endsWith(' twice') || words.endsWith(' once')) {
    times = words.endsWith(' twice') ? 2 : 1;
    words = words.substring(0, words.lastIndexOf(' '));
  }
  final id = _byPhrase[words];
  return id == null ? null : (id: id, times: times);
}

const _ctrl = 0xE0, _shiftKey = 0xE1, _altKey = 0xE2, _superKey = 0xE3;
const _tabKey = 0x2B, _left = 0x50, _right = 0x4F, _up = 0x52, _down = 0x51;

const _scrollNotches = 4;
const _moveStepPx = 120;

void _consumer(int usage) {
  final c = Connection.instance;
  c.key(0x8000 | usage, true);
  c.key(0x8000 | usage, false);
}

void _press(int hid) => Connection.instance.chord([], hid);

void _zoom(int notches) {
  final c = Connection.instance;
  c.key(_ctrl, true); // Ctrl + wheel = zoom, like a pinch on the pad
  c.scroll(0, notches);
  c.key(_ctrl, false);
}

/// The actions that are not in the round menu: what the touchpad does, plus a few more.
/// (label, what it does, asked about first)
final Map<String, (String, void Function(), bool)> _extra = {
  'scroll_up': (
    'Scroll up',
    () => Connection.instance.scroll(0, _scrollNotches),
    false,
  ),
  'scroll_down': (
    'Scroll down',
    () => Connection.instance.scroll(0, -_scrollNotches),
    false,
  ),
  'scroll_left': (
    'Scroll left',
    () => Connection.instance.scroll(-_scrollNotches, 0),
    false,
  ),
  'scroll_right': (
    'Scroll right',
    () => Connection.instance.scroll(_scrollNotches, 0),
    false,
  ),
  'scroll_top': (
    'Scroll to top',
    () => Connection.instance.chord([_ctrl], 0x4A),
    false,
  ),
  'scroll_bottom': (
    'Scroll to bottom',
    () => Connection.instance.chord([_ctrl], 0x4D),
    false,
  ),
  'volume_up': ('Volume up', () => _consumer(0xE9), false),
  'volume_down': ('Volume down', () => _consumer(0xEA), false),
  'mute': ('Mute', () => _consumer(0xE2), false),
  'brightness_up': ('Brightness up', () => _consumer(0x6F), false),
  'brightness_down': ('Brightness down', () => _consumer(0x70), false),
  'play_pause': ('Play / pause', () => _consumer(0xCD), false),
  'next_track': ('Next track', () => _consumer(0xB5), false),
  'prev_track': ('Previous track', () => _consumer(0xB6), false),
  'seek_forward': ('Seek forward', () => _press(_right), false),
  'seek_back': ('Seek back', () => _press(_left), false),
  'click': ('Click', () => Connection.instance.click(0), false),
  'right_click': ('Right click', () => Connection.instance.click(1), false),
  'middle_click': ('Middle click', () => Connection.instance.click(2), false),
  'double_click': (
    'Double click',
    () {
      Connection.instance.click(0);
      Connection.instance.click(0);
    },
    false,
  ),
  'drag_start': (
    'Hold the mouse button',
    () => Connection.instance.button(0, true),
    false,
  ),
  'drag_end': (
    'Release the mouse button',
    () => Connection.instance.button(0, false),
    false,
  ),
  'zoom_in': ('Zoom in', () => _zoom(2), false),
  'zoom_out': ('Zoom out', () => _zoom(-2), false),
  'workspace_left': (
    'Workspace left',
    () => Connection.instance.chord([_ctrl, _altKey], _left),
    false,
  ),
  'workspace_right': (
    'Workspace right',
    () => Connection.instance.chord([_ctrl, _altKey], _right),
    false,
  ),
  'overview': ('Overview', () => _press(_superKey), false),
  'screenshot': ('Screenshot', () => _press(0x46), false),
  'next_window': (
    'Next window',
    () => Connection.instance.chord([_altKey], _tabKey),
    false,
  ),
  'prev_window': (
    'Previous window',
    () => Connection.instance.chord([_altKey, _shiftKey], _tabKey),
    false,
  ),
  'next_tab': (
    'Next tab',
    () => Connection.instance.chord([_ctrl], _tabKey),
    false,
  ),
  'prev_tab': (
    'Previous tab',
    () => Connection.instance.chord([_ctrl, _shiftKey], _tabKey),
    false,
  ),
  'move_left': (
    'Move cursor left',
    () => Connection.instance.move(-_moveStepPx, 0),
    false,
  ),
  'move_right': (
    'Move cursor right',
    () => Connection.instance.move(_moveStepPx, 0),
    false,
  ),
  'move_up': (
    'Move cursor up',
    () => Connection.instance.move(0, -_moveStepPx),
    false,
  ),
  'move_down': (
    'Move cursor down',
    () => Connection.instance.move(0, _moveStepPx),
    false,
  ),
  'arrow_left': ('Arrow left', () => _press(_left), false),
  'arrow_right': ('Arrow right', () => _press(_right), false),
  'arrow_up': ('Arrow up', () => _press(_up), false),
  'arrow_down': ('Arrow down', () => _press(_down), false),
  'space': ('Space', () => _press(0x2C), false),
  'lock_screen': ('Lock screen', () => _consumer(0x19E), true),
};

/// The command for an action id, [times] over. Null for an id that is not known.
VoiceCommand? commandFor(String id, {int times = 1}) {
  final catalog = editCatalog[id];
  final extra = _extra[id];
  final void Function()? once = catalog?.run ?? extra?.$2;
  if (once == null) return null;
  final label = catalog?.label ?? extra!.$1;
  return VoiceCommand(id, times > 1 ? '$label x$times' : label, () {
    for (var i = 0; i < times; i++) {
      once();
    }
  }, risky: id == 'close_app' || (extra?.$3 ?? false));
}

/// A custom key of the round menu, by its name: say "reopen tab" for a key you called that.
VoiceCommand? customKeyCommand(String text) {
  final said = normalizePhrase(text);
  if (said.isEmpty) return null;
  for (final k in customKeys()) {
    if (normalizePhrase(k.label) == said) {
      final action = customAction(k);
      return VoiceCommand(k.id, k.label, action.run);
    }
  }
  return null;
}

// ---- dictation: typing text with key presses (US layout) ---------------------------------------

const _shift = 0xE1;
const _symbols = <String, (int, bool)>{
  ' ': (0x2C, false),
  '-': (0x2D, false),
  '=': (0x2E, false),
  '[': (0x2F, false),
  ']': (0x30, false),
  '\\': (0x31, false),
  ';': (0x33, false),
  "'": (0x34, false),
  '`': (0x35, false),
  ',': (0x36, false),
  '.': (0x37, false),
  '/': (0x38, false),
  '\n': (0x28, false),
  '_': (0x2D, true),
  '+': (0x2E, true),
  '{': (0x2F, true),
  '}': (0x30, true),
  '|': (0x31, true),
  ':': (0x33, true),
  '"': (0x34, true),
  '~': (0x35, true),
  '<': (0x36, true),
  '>': (0x37, true),
  '?': (0x38, true),
  '!': (0x1E, true),
  '@': (0x1F, true),
  '#': (0x20, true),
  r'$': (0x21, true),
  '%': (0x22, true),
  '^': (0x23, true),
  '&': (0x24, true),
  '*': (0x25, true),
  '(': (0x26, true),
  ')': (0x27, true),
};

/// The key (HID code) and whether Shift is held for a character; null for what a US keyboard
/// cannot type (accents, emoji ...).
(int, bool)? keyForChar(String ch) {
  if (ch.length != 1) return null;
  final u = ch.codeUnitAt(0);
  if (u >= 0x61 && u <= 0x7A) return (0x04 + u - 0x61, false);
  if (u >= 0x41 && u <= 0x5A) return (0x04 + u - 0x41, true);
  if (u >= 0x31 && u <= 0x39) return (0x1E + u - 0x31, false);
  if (u == 0x30) return (0x27, false);
  return _symbols[ch];
}

/// Types [text] on the computer, a character at a time (a pause every few keys so a slow link is
/// not flooded). Returns how many characters could not be typed and were left out.
Future<int> typeText(
  String text, {
  Duration pace = const Duration(milliseconds: 2),
}) async {
  final c = Connection.instance;
  var skipped = 0, n = 0;
  for (final rune in text.runes) {
    final k = keyForChar(String.fromCharCode(rune));
    if (k == null) {
      skipped++;
      continue;
    }
    if (k.$2) c.key(_shift, true);
    c.key(k.$1, true);
    c.key(k.$1, false);
    if (k.$2) c.key(_shift, false);
    if (++n % 8 == 0) await Future<void>.delayed(pace);
  }
  return skipped;
}
