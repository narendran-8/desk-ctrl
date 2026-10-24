import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';

import 'package:flutter/services.dart';

import 'connection.dart';
import 'key_sound.dart';
import 'settings.dart';

class KeyDef {
  final String label;
  final String? alt; // shifted symbol shown small above the label
  final int hid;
  final double flex;
  final KeyKind kind;
  final IconData? icon; // drawn above the label

  // What an F-key becomes while Fn is on (brightness, volume, media...).
  final int? fnHid;
  final String? fnLabel;
  final IconData? fnIcon;

  /// The Fn key itself: toggles the media layer instead of sending a key.
  final bool isFn;

  /// The combined Backspace / Del key (see [DeleteSwitchKey]).
  final bool isDeleteSwitch;

  /// Two keys stacked in one cell, each half the height (the Up / Down arrows).
  final List<KeyDef>? stack;

  const KeyDef(
    this.label,
    this.hid, {
    this.alt,
    this.flex = 1,
    this.kind = KeyKind.key,
    this.icon,
    this.fnHid,
    this.fnLabel,
    this.fnIcon,
    this.isFn = false,
    this.isDeleteSwitch = false,
    this.stack,
  });

  KeyDef get asFn => KeyDef(fnLabel ?? label, fnHid!, icon: fnIcon, kind: kind);
}

/// F1..F12 with Fn on. Codes: 0x8000 | HID consumer usage (see agent/src/hid.rs).
const _fnKeys = <(int, IconData, String)>[
  (0x8070, Icons.brightness_low, 'Dim'),
  (0x806F, Icons.brightness_high, 'Bright'),
  (0x80E2, Icons.volume_off, 'Mute'),
  (0x80EA, Icons.volume_down, 'Vol-'),
  (0x80E9, Icons.volume_up, 'Vol+'),
  (0x80B6, Icons.skip_previous, 'Prev'),
  (0x80CD, Icons.play_arrow, 'Play'),
  (0x80B5, Icons.skip_next, 'Next'),
  (0x819E, Icons.lock, 'Lock'),
  (0x46, Icons.screenshot_monitor, 'PrtSc'),
  (0x8192, Icons.calculate, 'Calc'),
  (0x8F01, Icons.mic_off, 'Mic'),
];

const _capsHid = 0x39;
const _shiftHids = {0xE1, 0xE5};

/// Which Shift keys are held right now, so the other keys can light up their shifted symbols.
class ShiftState extends ChangeNotifier {
  ShiftState._();
  static final ShiftState instance = ShiftState._();

  final Set<int> _held = {};

  bool get on => _held.isNotEmpty;

  void set(int hid, bool down) {
    final before = on;
    down ? _held.add(hid) : _held.remove(hid);
    if (before != on) notifyListeners();
  }
}

/// Colour of the shifted symbol while Shift is held.
const _shiftedColor = Color(0xFFFFD166);

List<KeyDef> _letters(String chars, List<int> hids) => [
  for (var i = 0; i < chars.length; i++)
    KeyDef(chars[i].toUpperCase(), hids[i]),
];

final List<List<KeyDef>> kLayout = [
  [
    const KeyDef('Esc', 0x29),
    for (var i = 0; i < 12; i++)
      KeyDef(
        'F${i + 1}',
        0x3A + i,
        fnHid: _fnKeys[i].$1,
        fnIcon: _fnKeys[i].$2,
        fnLabel: _fnKeys[i].$3,
      ),
    const KeyDef('Del', 0x4C),
  ],
  [
    const KeyDef('`', 0x35, alt: '~'),
    const KeyDef('1', 0x1E, alt: '!'),
    const KeyDef('2', 0x1F, alt: '@'),
    const KeyDef('3', 0x20, alt: '#'),
    const KeyDef('4', 0x21, alt: r'$'),
    const KeyDef('5', 0x22, alt: '%'),
    const KeyDef('6', 0x23, alt: '^'),
    const KeyDef('7', 0x24, alt: '&'),
    const KeyDef('8', 0x25, alt: '*'),
    const KeyDef('9', 0x26, alt: '('),
    const KeyDef('0', 0x27, alt: ')'),
    const KeyDef('-', 0x2D, alt: '_'),
    const KeyDef('=', 0x2E, alt: '+'),
    const KeyDef('Backspace', 0x2A, flex: 2),
  ],
  [
    const KeyDef('Tab', 0x2B, flex: 1.5),
    ..._letters('qwertyuiop', [
      0x14,
      0x1A,
      0x08,
      0x15,
      0x17,
      0x1C,
      0x18,
      0x0C,
      0x12,
      0x13,
    ]),
    const KeyDef('[', 0x2F, alt: '{'),
    const KeyDef(']', 0x30, alt: '}'),
    const KeyDef(r'\', 0x31, alt: '|', flex: 1.5),
  ],
  [
    const KeyDef('Caps', _capsHid, flex: 1.8),
    ..._letters('asdfghjkl', [
      0x04,
      0x16,
      0x07,
      0x09,
      0x0A,
      0x0B,
      0x0D,
      0x0E,
      0x0F,
    ]),
    const KeyDef(';', 0x33, alt: ':'),
    const KeyDef("'", 0x34, alt: '"'),
    const KeyDef('Enter', 0x28, flex: 2.2, kind: KeyKind.enter),
  ],
  [
    const KeyDef('Shift', 0xE1, flex: 2.3),
    ..._letters('zxcvbnm', [0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10]),
    const KeyDef(',', 0x36, alt: '<'),
    const KeyDef('.', 0x37, alt: '>'),
    const KeyDef('/', 0x38, alt: '?'),
    const KeyDef('Shift', 0xE5, flex: 2.7),
  ],
  [
    const KeyDef('Ctrl', 0xE0, flex: 1.4),
    const KeyDef('Super', 0xE3, flex: 1.2),
    const KeyDef('Alt', 0xE2, flex: 1.2),
    const KeyDef('', 0x2C, flex: 5, kind: KeyKind.space),
    const KeyDef('Alt', 0xE6, flex: 1.2),
    const KeyDef('Fn', 0, flex: 1.2, isFn: true),
    const KeyDef('Ctrl', 0xE4, flex: 1.4),
    const KeyDef('←', 0x50),
    const KeyDef('↓', 0x51),
    const KeyDef('↑', 0x52),
    const KeyDef('→', 0x4F),
  ],
];

const _backspaceHid = 0x2A;
const _deleteHid = 0x4C;

/// The rows to show. Without the function row, Esc moves to the start of the number
/// row and Del to its end, so those two keys are not lost with F1-F12. With
/// [joinDelete], Backspace and Del become one key and the separate Del is dropped.
List<List<KeyDef>> _baseLayout({
  required bool functionRow,
  bool joinDelete = false,
}) {
  final List<List<KeyDef>> rows;
  if (functionRow) {
    rows = kLayout;
  } else {
    final numbers = [
      const KeyDef('Esc', 0x29),
      for (final k in kLayout[1])
        if (k.label == 'Backspace')
          const KeyDef('Backspace', _backspaceHid, flex: 1.6)
        else
          k,
      const KeyDef('Del', _deleteHid),
    ];
    rows = [numbers, ...kLayout.sublist(2)];
  }
  if (!joinDelete) return rows;
  return [
    for (final row in rows)
      [
        for (final k in row)
          if (k.hid == _deleteHid)
            ...const <KeyDef>[]
          else if (k.hid == _backspaceHid)
            const KeyDef(
              'Backspace',
              _backspaceHid,
              flex: 2,
              isDeleteSwitch: true,
            )
          else
            k,
      ],
  ];
}

const _arrowHids = {0x50, 0x51, 0x52, 0x4F}; // left, down, up, right

/// Every row is this wide (in flex units), so every row ends exactly at the edge.
const _rowWidth = 15.0;

/// The keys as shown: [_baseLayout] with the arrow keys as on a laptop. Left and Right
/// are full-height; Up is stacked over Down in the cell between them, so Up is directly
/// above Down and nothing is left empty. Space takes whatever is left, so the bottom
/// row is as wide as the others whether or not the Fn key is shown ([showFn]).
List<List<KeyDef>> layoutFor({
  required bool functionRow,
  bool joinDelete = false,
  bool showFn = true,
}) {
  final rows = _baseLayout(functionRow: functionRow, joinDelete: joinDelete);
  final bottom = rows.last;
  KeyDef arrow(int hid) => bottom.firstWhere((k) => k.hid == hid);

  final rest = [
    for (final k in bottom)
      if (!_arrowHids.contains(k.hid) && (showFn || !k.isFn)) k,
  ];
  const cluster = 3.0; // Left, Up/Down, Right
  final others = rest
      .where((k) => k.kind != KeyKind.space)
      .fold(0.0, (sum, k) => sum + k.flex);
  final spaceFlex = _rowWidth - cluster - others;

  return [
    ...rows.sublist(0, rows.length - 1),
    [
      for (final k in rest)
        if (k.kind == KeyKind.space)
          KeyDef('', k.hid, flex: spaceFlex, kind: KeyKind.space)
        else
          k,
      arrow(0x50),
      KeyDef('', 0, stack: [arrow(0x52), arrow(0x51)]),
      arrow(0x4F),
    ],
  ];
}

/// Wider touch targets for the combined screen when the phone is upright.
/// Keep letters, numbers, modifiers, navigation and Backspace/Del available.
final portraitKeyboardLayout = <List<KeyDef>>[
  kLayout[1].sublist(1, 11), // 1–0
  kLayout[2].sublist(1, 11), // Q–P
  [...kLayout[3].sublist(1, 10), const KeyDef('Enter', 0x28, flex: 1.5)],
  [
    const KeyDef('Shift', 0xE1, flex: 1.4),
    ...kLayout[4].sublist(1, 8),
    const KeyDef('Backspace', _backspaceHid, flex: 1.8, isDeleteSwitch: true),
  ],
  [
    kLayout[1][0], // ` ~
    ...kLayout[1].sublist(11, 13), // - _  = +
    ...kLayout[2].sublist(11, 14), // [ {  ] }  \ |
    ...kLayout[3].sublist(10, 12), // ; :  ' "
    ...kLayout[4].sublist(8, 11), // , <  . >  / ?
  ],
  const [
    KeyDef('Esc', 0x29),
    KeyDef('Ctrl', 0xE0),
    KeyDef('Alt', 0xE2),
    KeyDef('', 0x2C, flex: 3, kind: KeyKind.space),
    KeyDef('←', 0x50),
    KeyDef('↓', 0x51),
    KeyDef('↑', 0x52),
    KeyDef('→', 0x4F),
  ],
];

class KeyboardScreen extends StatefulWidget {
  final bool compact;
  const KeyboardScreen({super.key, this.compact = false});

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  /// Fn layer on: F1..F12 act as brightness / volume / media keys.
  bool _fn = false;

  Widget _key(KeyDef k, bool fn) {
    if (k.stack != null) {
      return Column(
        children: [
          for (final half in k.stack!)
            Expanded(
              child: KeyButton(
                key: ValueKey('${half.label}${half.hid}'),
                def: half,
              ),
            ),
        ],
      );
    }
    if (k.isDeleteSwitch) return const DeleteSwitchKey();
    if (k.isFn) {
      return _FnKey(active: fn, onTap: () => setState(() => _fn = !_fn));
    }
    if (fn && k.fnHid != null) {
      return KeyButton(key: ValueKey('fn${k.fnHid}'), def: k.asFn);
    }
    return KeyButton(key: ValueKey('${k.label}${k.hid}'), def: k);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) {
        // With the Fn key switched off in Settings it is hidden and the F-row stays plain F-keys.
        final functionRow = Settings.instance.fnRow;
        final joinDelete = Settings.instance.joinDelete;
        final fnEnabled = Settings.instance.fnKey && functionRow;
        final fn = _fn && fnEnabled;
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            children: [
              for (final row
                  in widget.compact
                      ? portraitKeyboardLayout
                      : layoutFor(
                          functionRow: functionRow,
                          joinDelete: joinDelete,
                          showFn: fnEnabled,
                        ))
                Expanded(
                  child: Row(
                    children: [
                      for (final k in row)
                        Expanded(
                          flex: (k.flex * 10).round(),
                          child: _key(k, fn),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Backspace and Del on one key. Press it to delete backwards; swipe it sideways
/// to switch to Del (and back). The key shows the current one and the other in small type.
///
/// The key is pressed a moment after the finger lands, so a swipe never deletes a
/// character; holding still behaves like a normal key, including holding to repeat.
class DeleteSwitchKey extends StatefulWidget {
  const DeleteSwitchKey({super.key});

  @override
  State<DeleteSwitchKey> createState() => _DeleteSwitchKeyState();
}

class _DeleteSwitchKeyState extends State<DeleteSwitchKey> {
  /// Which one the key is on (kept while the app runs, shared by every instance).
  static final ValueNotifier<bool> _showDel = ValueNotifier(false);

  static const _pressDelay = Duration(milliseconds: 110);
  static const _swipeDistance = 18.0;

  int? _pointer;
  Offset _start = Offset.zero;
  bool _swiped = false;
  int? _heldHid; // the key we have sent "down" for
  Timer? _timer;

  int get _hid => _showDel.value ? _deleteHid : _backspaceHid;

  void _feedback() {
    KeySound.instance.play(KeyKind.key);
    if (Settings.instance.haptic) HapticFeedback.selectionClick();
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    setState(() {
      _pointer = e.pointer;
      _start = e.position;
      _swiped = false;
    });
    _timer = Timer(_pressDelay, _press);
  }

  void _press() {
    if (_pointer == null || _swiped || _heldHid != null) return;
    _heldHid = _hid;
    Connection.instance.key(_heldHid!, true);
    _feedback();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _swiped || _heldHid != null) return;
    final d = e.position - _start;
    if (d.dx.abs() > _swipeDistance && d.dx.abs() > d.dy.abs()) {
      _swiped = true;
      _timer?.cancel();
      _showDel.value = !_showDel.value;
      if (Settings.instance.haptic) HapticFeedback.mediumImpact();
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _timer?.cancel();
    final held = _heldHid;
    if (held != null) {
      Connection.instance.key(held, false);
    } else if (!_swiped) {
      // A quick tap, released before the press delay.
      final hid = _hid;
      Connection.instance.key(hid, true);
      Connection.instance.key(hid, false);
      _feedback();
    }
    setState(() {
      _pointer = null;
      _heldHid = null;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_heldHid != null) Connection.instance.key(_heldHid!, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _heldHid != null;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 40),
          decoration: BoxDecoration(
            color: pressed ? context.desk.accent : context.desk.key,
            borderRadius: BorderRadius.circular(6),
            boxShadow: pressed
                ? null
                : const [
                    BoxShadow(color: Colors.black54, offset: Offset(0, 2)),
                  ],
          ),
          alignment: Alignment.center,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showDel,
            builder: (context, del, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0.4, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: FittedBox(
                key: ValueKey(del),
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      del ? 'Del' : 'Backspace',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      del ? '\u2039 Backspace \u203A' : '\u2039 Del \u203A',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Latching Fn key: tap to switch the F-row to media keys, tap again to go back.
class _FnKey extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _FnKey({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        KeySound.instance.play(KeyKind.key);
        if (Settings.instance.haptic) HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: active ? context.desk.accent : context.desk.key,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(color: Colors.black54, offset: Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'Fn',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// One physical-style key. Uses raw pointer events (not gestures) so that
/// many fingers can press different keys at the same moment.
class KeyButton extends StatefulWidget {
  final KeyDef def;
  const KeyButton({super.key, required this.def});

  @override
  State<KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<KeyButton> {
  final Set<int> _pointers = {};

  bool get _pressed => _pointers.isNotEmpty;

  void _down(PointerDownEvent e) {
    final first = _pointers.isEmpty;
    setState(() => _pointers.add(e.pointer));
    if (!first) return;
    Connection.instance.key(widget.def.hid, true);
    if (_shiftHids.contains(widget.def.hid)) {
      ShiftState.instance.set(widget.def.hid, true);
    }
    KeySound.instance.play(widget.def.kind);
    if (Settings.instance.haptic) HapticFeedback.selectionClick();
  }

  void _up(PointerEvent e) {
    if (!_pointers.contains(e.pointer)) return;
    setState(() => _pointers.remove(e.pointer));
    if (_pointers.isEmpty) {
      Connection.instance.key(widget.def.hid, false);
      if (_shiftHids.contains(widget.def.hid)) {
        ShiftState.instance.set(widget.def.hid, false);
      }
    }
  }

  @override
  void dispose() {
    if (_pointers.isNotEmpty) {
      Connection.instance.key(widget.def.hid, false);
      final hid = widget.def.hid;
      // Not now: listeners must not be told while the tree is being torn down.
      if (_shiftHids.contains(hid)) {
        Future.microtask(() => ShiftState.instance.set(hid, false));
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.def.alt == null) return _buildKey(context, false);
    return ListenableBuilder(
      listenable: ShiftState.instance,
      builder: (context, _) => _buildKey(context, ShiftState.instance.on),
    );
  }

  /// [shifted]: Shift is held and this key has a second symbol, so show that one.
  Widget _buildKey(BuildContext context, bool shifted) {
    final d = widget.def;
    final isMod = d.label.length > 1 && d.hid >= 0xE0 || d.label.length > 2;
    final bg = _pressed
        ? context.desk.accent
        : shifted
        ? context.desk.keyMod
        : isMod
        ? context.desk.key
        : context.desk.keyAlt;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 40),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: shifted && !_pressed
                ? Border.all(color: _shiftedColor.withAlpha(140))
                : null,
            boxShadow: _pressed
                ? null
                : const [
                    BoxShadow(color: Colors.black54, offset: Offset(0, 2)),
                  ],
          ),
          alignment: Alignment.center,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (d.alt != null)
                      Text(
                        d.alt!,
                        style: shifted
                            ? const TextStyle(
                                color: _shiftedColor,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              )
                            : const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                      ),
                    if (d.icon != null)
                      Icon(d.icon, size: 20, color: Colors.white),
                    Text(
                      d.label,
                      style: TextStyle(
                        color: shifted
                            ? Colors.white30
                            : d.icon != null
                            ? Colors.white70
                            : Colors.white,
                        fontSize: shifted
                            ? 11
                            : (d.icon != null ? 9 : (isMod ? 13 : 17)),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (d.hid == _capsHid)
                Positioned(top: 5, left: 7, child: const _CapsLight()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Caps Lock light: lit while Caps Lock is on at the computer.
class _CapsLight extends StatelessWidget {
  const _CapsLight();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Connection.instance,
      builder: (context, _) {
        final on = Connection.instance.capsOn;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? const Color(0xFF39FF88) : const Color(0xFF14161B),
            border: Border.all(color: Colors.black54),
            boxShadow: on
                ? const [
                    BoxShadow(
                      color: Color(0xAA39FF88),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}
