import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'connection.dart';
import 'custom_key.dart';
import 'settings.dart';

const _ctrl = 0xE0, _shift = 0xE1;
const _enter = 0x28, _backspace = 0x2A, _delete = 0x4C, _f5 = 0x3E;
const _c = 0x06, _x = 0x1B, _v = 0x19, _z = 0x1D, _a = 0x04;
const _y = 0x1C, _f = 0x09, _s = 0x16, _t = 0x17, _w = 0x1A;
const _alt = 0xE2, _f4 = 0x3D;
const _esc = 0x29, _tab = 0x2B, _home = 0x4A, _end = 0x4D;
const _pageUp = 0x4B, _pageDown = 0x4E;

/// One wedge of the fan menu.
class EditAction {
  final String label;

  /// The picture on the wedge, in the colour it is given (black on white, white on black).
  final Widget Function(Color color) icon;
  final void Function() run;

  /// Holding a finger on the option repeats it (Backspace, Delete and Enter: delete a paragraph
  /// by holding Backspace).
  final bool repeats;

  /// The name saved in the settings.
  final String id;
  const EditAction(
    this.label,
    this.icon,
    this.run, {
    this.repeats = false,
    this.id = '',
  });
}

Widget _icon(IconData d, Color c) => Icon(d, size: 26, color: c);

/// A terminal icon with a small badge, for the terminal's own copy / paste.
Widget _terminal(IconData badge, Color c) => SizedBox(
  width: 30,
  height: 30,
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(Icons.terminal, size: 28, color: c),
      Positioned(right: -6, bottom: -6, child: Icon(badge, size: 15, color: c)),
    ],
  ),
);

void _press(int hid) {
  Connection.instance.key(hid, true);
  Connection.instance.key(hid, false);
}

void _ctrlKey(int hid) => Connection.instance.chord([_ctrl], hid);

/// Terminals use Ctrl+Shift+C / V: plain Ctrl+C stops the running program there.
void _terminalKey(int hid) => Connection.instance.chord([_ctrl, _shift], hid);

Widget _flipped(IconData d, Color c) =>
    Transform.flip(flipX: true, child: _icon(d, c));

EditAction _key(
  String id,
  String label,
  Widget Function(Color) icon,
  void Function() run, {
  bool repeats = false,
}) => EditAction(label, icon, run, repeats: repeats, id: id);

/// Every option that can be put in the menu, by the id that is saved in the settings.
final Map<String, EditAction> editCatalog = {
  for (final a in <EditAction>[
    _key(
      'copy',
      'Copy',
      (c) => _icon(Icons.content_copy, c),
      () => _ctrlKey(_c),
    ),
    _key('cut', 'Cut', (c) => _icon(Icons.content_cut, c), () => _ctrlKey(_x)),
    _key(
      'paste',
      'Paste',
      (c) => _icon(Icons.content_paste, c),
      () => _ctrlKey(_v),
    ),
    _key('undo', 'Undo', (c) => _icon(Icons.undo, c), () => _ctrlKey(_z)),
    _key(
      'select_all',
      'Select all',
      (c) => _icon(Icons.select_all, c),
      () => _ctrlKey(_a),
    ),
    _key('redo', 'Redo', (c) => _icon(Icons.redo, c), () => _ctrlKey(_y)),
    _key('find', 'Find', (c) => _icon(Icons.search, c), () => _ctrlKey(_f)),
    _key(
      'save',
      'Save',
      (c) => _icon(Icons.save_outlined, c),
      () => _ctrlKey(_s),
    ),
    _key(
      'terminal_copy',
      'Terminal copy',
      (c) => _terminal(Icons.content_copy, c),
      () => _terminalKey(_c),
    ),
    _key(
      'terminal_paste',
      'Terminal paste',
      (c) => _terminal(Icons.content_paste, c),
      () => _terminalKey(_v),
    ),
    _key(
      'enter',
      'Enter',
      (c) => _icon(Icons.keyboard_return, c),
      () => _press(_enter),
      repeats: true,
    ),
    _key(
      'backspace',
      'Backspace',
      (c) => _icon(Icons.backspace_outlined, c),
      () => _press(_backspace),
      repeats: true,
    ),
    // The Delete key removes what is ahead of the cursor: Backspace turned round.
    _key(
      'delete',
      'Delete',
      (c) => _flipped(Icons.backspace_outlined, c),
      () => _press(_delete),
      repeats: true,
    ),
    _key('escape', 'Escape', (c) => _icon(Icons.close, c), () => _press(_esc)),
    _key(
      'tab',
      'Tab',
      (c) => _icon(Icons.keyboard_tab, c),
      () => _press(_tab),
      repeats: true,
    ),
    _key(
      'refresh',
      'Refresh',
      (c) => _icon(Icons.refresh, c),
      () => _press(_f5),
    ),
    _key(
      'home',
      'Home',
      (c) => _icon(Icons.first_page, c),
      () => _press(_home),
    ),
    _key('end', 'End', (c) => _icon(Icons.last_page, c), () => _press(_end)),
    _key(
      'page_up',
      'Page up',
      (c) => _icon(Icons.keyboard_double_arrow_up, c),
      () => _press(_pageUp),
      repeats: true,
    ),
    _key(
      'page_down',
      'Page down',
      (c) => _icon(Icons.keyboard_double_arrow_down, c),
      () => _press(_pageDown),
      repeats: true,
    ),
    // Ctrl+Alt+T: the shortcut that opens a terminal on Ubuntu, GNOME, KDE and most desktops.
    _key(
      'open_terminal',
      'Open terminal',
      (c) => _icon(Icons.terminal, c),
      () => Connection.instance.chord([_ctrl, _alt], _t),
    ),
    // Alt+F4 closes the window in focus (the program asks to save first if it has changes).
    _key(
      'close_app',
      'Close application',
      (c) => _icon(Icons.cancel_presentation, c),
      () => Connection.instance.chord([_alt], _f4),
    ),
    _key(
      'new_tab',
      'New tab',
      (c) => _icon(Icons.add_box_outlined, c),
      () => _ctrlKey(_t),
    ),
    _key(
      'close_tab',
      'Close tab',
      (c) => _icon(Icons.tab_unselected, c),
      () => _ctrlKey(_w),
    ),
  ])
    a.id: a,
};

/// The user's own keys, from the settings.
List<CustomKey> customKeys() =>
    CustomKey.decodeList(Settings.instance.editCustom);

/// A small keycap: the modifiers over the key, in the colour of the wedge.
Widget _keycap(CustomKey k, Color c) => FittedBox(
  child: Container(
    width: 34,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: c, width: 1.5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (k.mods != 0)
          Text(
            k.modInitials,
            style: TextStyle(color: c, fontSize: 8, height: 1),
          ),
        Text(
          shortKeyName(k.key),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: c,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
      ],
    ),
  ),
);

/// The menu option for a custom key: its modifiers and key pressed together.
EditAction customAction(CustomKey k) => EditAction(
  k.label,
  (c) => _keycap(k, c),
  () => Connection.instance.chord(k.modKeys, k.key),
  repeats: k.repeats,
  id: k.id,
);

/// The option with this id: a built-in one, or one of the user's own keys. Null if there is none
/// (a custom key that was deleted).
EditAction? editActionFor(String id) {
  final builtIn = editCatalog[id];
  if (builtIn != null) return builtIn;
  for (final k in customKeys()) {
    if (k.id == id) return customAction(k);
  }
  return null;
}

/// The rows the menu has until the user changes them (ids from [editCatalog]).
const defaultEditLayout = <List<String>>[
  ['copy', 'cut', 'paste', 'undo', 'select_all'],
  ['terminal_copy', 'terminal_paste', 'enter', 'backspace', 'delete'],
  ['refresh', 'open_terminal', 'close_app'],
];

/// At most this many rows and this many options in a row (the rows must fit a portrait phone).
const maxEditRows = 3, maxEditPerRow = 6;

/// A layout as one string for the settings: rows split by ';', ids by ','.
String encodeEditLayout(List<List<String>> rows) =>
    rows.map((r) => r.join(',')).join(';');

/// Reads a saved layout. Unknown ids are dropped, empty rows vanish, the limits are kept. An
/// empty or unreadable text gives the default layout.
List<List<String>> decodeEditLayout(String text) {
  final rows = <List<String>>[
    for (final row in text.split(';'))
      [
        for (final id in row.split(','))
          if (editActionFor(id) != null) id,
      ].take(maxEditPerRow).toList(),
  ].where((r) => r.isNotEmpty).take(maxEditRows).toList();
  return rows.isEmpty
      ? [
          for (final r in defaultEditLayout) [...r],
        ]
      : rows;
}

/// The rings, inside out: what the menu shows now. [applyEditLayout] changes it.
final editRings = <List<EditAction>>[
  for (final row in defaultEditLayout) [for (final id in row) editCatalog[id]!],
];

void applyEditLayout(String text) {
  editRings
    ..clear()
    ..addAll([
      for (final row in decodeEditLayout(text))
        [for (final id in row) editActionFor(id)!],
    ]);
}

final editActions = [for (final id in defaultEditLayout[0]) editCatalog[id]!];
final terminalActions = [
  for (final id in defaultEditLayout[1]) editCatalog[id]!,
];
final refreshActions = [
  for (final id in defaultEditLayout[2]) editCatalog[id]!,
];

/// The button in the top corner. Two ways to use it, like the radial menu of remote-desktop apps:
///  - hold it: the menu expands, drag onto an option and lift your finger there to run it. Lifting
///    anywhere else folds the menu away; lifting without having left the button leaves it open;
///  - tap it: the menu opens and stays; tap an option to run it, or anywhere else to close it.
/// Running an option always closes the menu.
class EditMenuButton extends StatefulWidget {
  const EditMenuButton({super.key});

  /// How long the button must be held before the menu expands.
  static const holdTime = Duration(milliseconds: 220);

  @override
  State<EditMenuButton> createState() => _EditMenuButtonState();
}

class _EditMenuButtonState extends State<EditMenuButton> {
  Timer? _hold;
  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _moved = false;

  // The menu is one overlay on top of everything, in both ways of using it. While the button is
  // held it follows the finger ([_finger] is set); otherwise it takes touches itself.
  OverlayEntry? _entry;
  final _finger = ValueNotifier<Offset?>(null);
  Offset _origin = Offset.zero;
  int _sx = 1, _sy = 1;

  Offset _centre() {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downAt = e.position;
    _moved = false;
    _hold = Timer(EditMenuButton.holdTime, () => _open(held: true));
  }

  /// A menu left open and untouched folds itself away after this long.
  Timer? _idle;

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(
      Duration(seconds: Settings.instance.editMenuIdleSeconds),
      _close,
    );
  }

  void _open({required bool held}) {
    if (!mounted || _entry != null) return;
    applyEditLayout(Settings.instance.editLayout);
    _origin = _centre();
    final dir = EditFan.directionFor(_origin, MediaQuery.of(context).size);
    _sx = dir.$1;
    _sy = dir.$2;
    _finger.value = held ? _downAt : null;
    if (held && Settings.instance.haptic) HapticFeedback.mediumImpact();
    _entry = OverlayEntry(
      builder: (_) => EditFan(
        origin: _origin,
        sx: _sx,
        sy: _sy,
        finger: _finger,
        onPick: _tapped,
        onRepeat: _repeated,
        onActivity: _armIdle,
        onClose: _close,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    if (!held) _armIdle();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if ((e.position - _downAt).distance > 12) _moved = true;
    if (_entry != null && _finger.value != null) _finger.value = e.position;
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _hold?.cancel();
    if (_entry != null && _finger.value != null) {
      // Lifted after holding.
      final w = e is PointerUpEvent
          ? EditFan.wedgeAt(e.position - _origin, sx: _sx, sy: _sy)
          : null;
      if (w != null) {
        _pickAndClose(w); // dragged onto an option and lifted: run it, close
      } else if (e is PointerUpEvent &&
          (e.position - _origin).distance < EditFan.innerRadius(0)) {
        _finger.value =
            null; // never left the button: leave the menu open to tap an option
        _armIdle();
      } else {
        _close();
      }
    } else if (_entry == null && e is PointerUpEvent && !_moved) {
      _open(held: false); // a quick tap: open and stay
    }
  }

  /// Dragged onto an option and lifted: close the menu, then do it.
  void _pickAndClose((int, int) wedge) {
    _close();
    if (Settings.instance.haptic) HapticFeedback.selectionClick();
    editRings[wedge.$1][wedge.$2].run();
  }

  /// An option was tapped in the open menu: do it. The menu stays for the next tap (Backspace
  /// again, Enter again ...), unless the setting says to close it.
  void _tapped((int, int) wedge) {
    if (Settings.instance.haptic) HapticFeedback.selectionClick();
    editRings[wedge.$1][wedge.$2].run();
    if (Settings.instance.editMenuStayOpen) {
      _armIdle();
    } else {
      _close();
    }
  }

  /// A finger held on Backspace, Delete or Enter: once more.
  void _repeated((int, int) wedge) {
    editRings[wedge.$1][wedge.$2].run();
    _armIdle();
  }

  void _close() {
    _idle?.cancel();
    final entry = _entry;
    _entry = null;
    _finger.value = null;
    entry?.remove();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _idle?.cancel();
    _close();
    _finger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: IconButton(
        // No tooltip: holding the button would pop it up behind the menu.
        icon: const Icon(Icons.content_copy, size: 20),
        onPressed: () {}, // the Listener above does the work; this only gives the touch feedback
      ),
    );
  }
}

/// The menu itself: two quarter rings around [origin], black and white. It opens towards the
/// middle of the screen: right and down from a button in the top-left corner, left and down
/// from one in the top-right corner (the bar moves to the other side when the phone is turned
/// the other way round), and upwards from a button near the bottom. A tap outside closes it.
class EditFan extends StatefulWidget {
  final Offset origin;

  /// Which way the rings open: +1 / -1 across (x) and down (y).
  final int sx, sy;

  /// Where the finger is while the button is held (null: not held). Held, the fan only shows what
  /// is under the finger and the button does the lifting; otherwise the fan takes touches itself.
  final ValueListenable<Offset?> finger;

  /// An option was tapped.
  final void Function((int, int) wedge) onPick;

  /// A finger is being held on an option that repeats: do it once more.
  final void Function((int, int) wedge) onRepeat;

  /// Something touched the menu (keeps it from folding away while it is in use).
  final VoidCallback onActivity;

  /// Close the menu: a tap outside the rings, or the screen was turned.
  final VoidCallback onClose;
  const EditFan({
    super.key,
    required this.origin,
    required this.finger,
    required this.onPick,
    required this.onRepeat,
    required this.onActivity,
    required this.onClose,
    this.sx = 1,
    this.sy = 1,
  });

  /// The direction that points into the screen from [origin].
  static (int, int) directionFor(Offset origin, Size screen) => (
    origin.dx <= screen.width / 2 ? 1 : -1,
    origin.dy <= screen.height / 2 ? 1 : -1,
  );

  /// Where ring [ring] starts and ends (distance from the button).
  /// Three rows, each 80 px deep; the last one still fits a portrait phone (360 wide).
  static const _bands = [(48.0, 128.0), (132.0, 212.0), (216.0, 296.0)];
  static double innerRadius(int ring) => _bands[ring].$1;
  static double outerRadius(int ring) => _bands[ring].$2;
  static double midRadius(int ring) =>
      (innerRadius(ring) + outerRadius(ring)) / 2;
  static double get reach => _bands.last.$2;

  /// The angle one wedge of ring [ring] covers.
  /// The options of a row share the whole quarter: fewer options, wider wedges.
  static double sweep(int ring) => (math.pi / 2) / editRings[ring].length;

  /// Which wedge is at [p] (relative to the origin): (ring, index), or null. Wedge 0 is the
  /// one nearest the horizontal line through the origin, the last the one nearest the vertical.
  static (int, int)? wedgeAt(Offset p, {int sx = 1, int sy = 1}) {
    final q = Offset(
      p.dx * sx,
      p.dy * sy,
    ); // mirror into the right / down quadrant
    final r = q.distance;
    final a = math.atan2(
      q.dy,
      q.dx,
    ); // 0 = along the horizontal, pi/2 = vertical
    if (a < 0 || a >= math.pi / 2) return null;
    for (var ring = 0; ring < editRings.length; ring++) {
      if (r >= innerRadius(ring) && r <= outerRadius(ring)) {
        final index = (a / sweep(ring)).floor();
        return index < editRings[ring].length ? (ring, index) : null;
      }
    }
    return null;
  }

  /// The point at [radius] and [angle] (in the mirrored quadrant) around [origin].
  static Offset pointAt(
    Offset origin,
    int sx,
    int sy,
    double radius,
    double angle,
  ) => origin + Offset(math.cos(angle) * sx, math.sin(angle) * sy) * radius;

  /// The middle of one wedge, where its picture goes.
  static Offset centreOf(Offset origin, int sx, int sy, int ring, int index) =>
      pointAt(origin, sx, sy, midRadius(ring), (index + 0.5) * sweep(ring));

  @override
  State<EditFan> createState() => _EditFanState();
}

class _EditFanState extends State<EditFan> with WidgetsBindingObserver {
  (int, int)? _hot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.finger.addListener(_fromFinger);
    final p = widget.finger.value;
    if (p != null) _hot = _wedge(p);
  }

  void _fromFinger() {
    final p = widget.finger.value;
    if (mounted) setState(() => _hot = p == null ? null : _wedge(p));
  }

  @override
  void dispose() {
    _stopRepeat();
    widget.finger.removeListener(_fromFinger);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The screen was turned: the button is somewhere else now, so close the menu rather than
  /// leave it hanging where the button used to be.
  @override
  void didChangeMetrics() {
    if (mounted) widget.onClose();
  }

  (int, int)? _wedge(Offset global) =>
      EditFan.wedgeAt(global - widget.origin, sx: widget.sx, sy: widget.sy);

  // Holding a finger on Backspace / Delete / Enter repeats it, like holding the key: nothing
  // for a moment (so a tap is a single press), then steadily, faster after a second.
  static const _repeatAfter = Duration(milliseconds: 350);
  Timer? _delay, _again;
  (int, int)? _pressed;
  bool _didRepeat = false;
  int _ticks = 0;

  void _stopRepeat() {
    _delay?.cancel();
    _again?.cancel();
    _delay = _again = null;
  }

  void _startRepeat((int, int) w) {
    _delay = Timer(_repeatAfter, () {
      if (!mounted || _hot != w) return;
      _didRepeat = true;
      _ticks = 0;
      widget.onRepeat(w);
      _again = Timer.periodic(const Duration(milliseconds: 30), (_) {
        // About 16 presses a second for the first second and a bit, then about 33.
        _ticks++;
        if (_ticks < 40 && _ticks.isOdd) return;
        if (mounted && _hot == w) widget.onRepeat(w);
      });
    });
  }

  void _track(PointerEvent e) {
    final w = _wedge(e.position);
    setState(() => _hot = w);
    widget.onActivity();
    if (e is PointerDownEvent) {
      _pressed = w;
      _didRepeat = false;
      _stopRepeat();
      if (w != null &&
          Settings.instance.editMenuHoldRepeat &&
          editRings[w.$1][w.$2].repeats) {
        _startRepeat(w);
      }
    } else if (w != _pressed) {
      _stopRepeat(); // slid off the option: no more repeats
      _pressed = null;
    }
  }

  void _release(PointerEvent e) {
    _stopRepeat();
    final w = _wedge(e.position);
    if (_didRepeat) {
      _didRepeat = false; // it was a hold, not a tap: already done
      return;
    }
    if (w != null) {
      widget.onPick(w);
    } else {
      widget.onClose(); // a tap outside the rings
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final label = _hot == null ? null : editRings[_hot!.$1][_hot!.$2].label;
    final tip = EditFan.pointAt(
      widget.origin,
      widget.sx,
      widget.sy,
      EditFan.reach + 12,
      0,
    );
    // Held: the button follows the finger and does the lifting, so the fan takes no touches.
    final held = widget.finger.value != null;
    return IgnorePointer(
      ignoring: held,
      child: Listener(
        behavior:
            HitTestBehavior.opaque, // nothing under the menu gets the touch
        onPointerDown: _track,
        onPointerMove: _track,
        onPointerUp: _release,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // The menu is an overlay: it darkens the screen itself.
              const Positioned.fill(child: ColoredBox(color: Colors.black54)),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _FanPainter(
                      widget.origin,
                      widget.sx,
                      widget.sy,
                      _hot,
                    ),
                  ),
                ),
              ),
              // The menu is drawn over the button and dims it, so the button is drawn again here,
              // in the accent colour: it shows the menu is held / open.
              Positioned(
                left: widget.origin.dx - 22,
                top: widget.origin.dy - 22,
                child: IgnorePointer(
                  child: Container(
                    key: const Key('editButtonActive'),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.desk.accent,
                    ),
                    child: const Icon(
                      Icons.content_copy,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              for (var ring = 0; ring < editRings.length; ring++)
                for (var i = 0; i < editRings[ring].length; i++)
                  Builder(
                    builder: (_) {
                      final p = EditFan.centreOf(
                        widget.origin,
                        widget.sx,
                        widget.sy,
                        ring,
                        i,
                      );
                      final on = _hot == (ring, i);
                      return Positioned(
                        left: p.dx - 17,
                        top: p.dy - 17,
                        child: IgnorePointer(
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Center(
                              child: editRings[ring][i].icon(
                                _FanPainter.iconColor(ring, on),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              if (label != null)
                Positioned(
                  top: tip.dy - 6,
                  // Past the end of the rings, on the side they open towards.
                  left: widget.sx > 0 ? tip.dx : null,
                  right: widget.sx < 0 ? screen.width - tip.dx : null,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Black and white: the inner ring is white with black pictures, the outer ring black with white
/// ones, and the wedge under the finger swaps its colours.
class _FanPainter extends CustomPainter {
  final Offset origin;
  final int sx, sy;
  final (int, int)? hot;
  _FanPainter(this.origin, this.sx, this.sy, this.hot);

  static const _black = Color(0xFF000000), _white = Color(0xFFFFFFFF);

  // Rows alternate: white with black pictures, black with white pictures, white ...
  static Color fill(int ring, bool on) => ring.isEven != on ? _white : _black;
  static Color iconColor(int ring, bool on) =>
      ring.isEven != on ? _black : _white;

  /// The angle (on screen) of [theta] in the mirrored quadrant.
  double _screen(double theta) =>
      math.atan2(sy * math.sin(theta), sx * math.cos(theta));

  @override
  void paint(Canvas canvas, Size size) {
    final dir = (sx * sy)
        .toDouble(); // mirroring once flips the direction of the arcs
    for (var ring = 0; ring < editRings.length; ring++) {
      final outer = Rect.fromCircle(
        center: origin,
        radius: EditFan.outerRadius(ring),
      );
      final inner = Rect.fromCircle(
        center: origin,
        radius: EditFan.innerRadius(ring),
      );
      final sweep = EditFan.sweep(ring);
      for (var i = 0; i < editRings[ring].length; i++) {
        final a = i * sweep, b = a + sweep;
        final path = Path()
          ..arcTo(outer, _screen(a), dir * sweep, false)
          ..arcTo(inner, _screen(b), -dir * sweep, false)
          ..close();
        canvas.drawPath(path, Paint()..color = fill(ring, hot == (ring, i)));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ring.isEven ? _black : _white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FanPainter old) =>
      old.hot != hot || old.origin != origin || old.sx != sx || old.sy != sy;
}
