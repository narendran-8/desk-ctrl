import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';

import 'package:flutter/services.dart';

import 'modes.dart';
import 'settings.dart';

/// Where the long-press menu opens, relative to the button.
enum MenuSide { right, left, below }

/// One button that stands for all modes. It shows the current mode.
///  - one tap: back to the mode you were on before (keyboard -> trackpad, tap again -> keyboard);
///    the very first time, the next mode
///  - double tap: the next mode in your order, again and again (keyboard -> trackpad -> mouse -> computer ...)
///  - long-press: a menu with the other modes opens; drag onto one and let go to pick it
class ModeButton extends StatefulWidget {
  final Mode mode;
  final List<Mode> modes;
  final ValueChanged<Mode> onMode;
  final MenuSide side;

  /// The mode shown before this one (a single tap goes back to it); null: none yet.
  final Mode? previous;

  /// Show the mode's name next to the icon (the wide top bar).
  final bool showLabel;

  const ModeButton({
    super.key,
    required this.mode,
    required this.modes,
    required this.onMode,
    this.side = MenuSide.below,
    this.previous,
    this.showLabel = false,
  });

  @override
  State<ModeButton> createState() => _ModeButtonState();
}

/// A second tap this soon after the first is a double tap. A single tap therefore takes effect
/// this long after the finger lifts.
const modeDoubleTapWindow = Duration(milliseconds: 260);

class _ModeButtonState extends State<ModeButton> {
  Timer? _singleTap;

  static const _holdTime = Duration(milliseconds: 380);
  static const _slop = 14.0;
  static const _itemWidth = 184.0, _itemHeight = 48.0, _gap = 6.0;

  Timer? _timer;
  Offset _downAt = Offset.zero;
  bool _moved = false;
  OverlayEntry? _menu;
  final ValueNotifier<Mode?> _hover = ValueNotifier(null);
  final Map<Mode, GlobalKey> _itemKeys = {};

  List<Mode> get _others => [
    for (final m in widget.modes)
      if (m != widget.mode) m,
  ];

  void _onDown(PointerDownEvent e) {
    _downAt = e.position;
    _moved = false;
    _timer?.cancel();
    _timer = Timer(_holdTime, _openMenu);
  }

  void _onMove(PointerMoveEvent e) {
    if (_menu != null) {
      _hover.value = _hit(e.position);
    } else if ((e.position - _downAt).distance > _slop) {
      _moved = true; // a drag, not a tap or a long-press
      _timer?.cancel();
    }
  }

  void _onUp(PointerUpEvent e) {
    _timer?.cancel();
    if (_menu != null) {
      final pick = _hit(e.position);
      _closeMenu();
      if (pick != null) widget.onMode(pick);
    } else if (!_moved && widget.modes.length > 1) {
      if (_singleTap?.isActive ?? false) {
        // A second tap: on to the next mode in the order.
        _singleTap!.cancel();
        widget.onMode(nextMode(widget.modes, widget.mode));
      } else {
        _singleTap = Timer(modeDoubleTapWindow, () {
          final back = widget.previous;
          widget.onMode(
            back != null && back != widget.mode && widget.modes.contains(back)
                ? back
                : nextMode(widget.modes, widget.mode),
          );
        });
      }
    }
  }

  void _onCancel(PointerCancelEvent e) {
    _timer?.cancel();
    _closeMenu();
  }

  Mode? _hit(Offset p) {
    for (final m in _others) {
      final box =
          _itemKeys[m]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) {
        continue;
      }
      final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(
        _gap / 2 + 2,
      );
      if (rect.contains(p)) {
        return m;
      }
    }
    return null;
  }

  void _openMenu() {
    final others = _others;
    if (others.isEmpty || !mounted) return;
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(context);
    final height = others.length * _itemHeight + (others.length - 1) * _gap;

    var left = switch (widget.side) {
      MenuSide.right => anchor.right + 8,
      MenuSide.left => anchor.left - 8 - _itemWidth,
      MenuSide.below => anchor.center.dx - _itemWidth / 2,
    };
    var top = switch (widget.side) {
      MenuSide.below => anchor.bottom + 8,
      _ => anchor.center.dy - height / 2,
    };
    left = left.clamp(
      8.0,
      (screen.width - _itemWidth - 8).clamp(8.0, double.infinity),
    );
    top = top.clamp(
      8.0,
      (screen.height - height - 8).clamp(8.0, double.infinity),
    );

    _itemKeys
      ..clear()
      ..addEntries([for (final m in others) MapEntry(m, GlobalKey())]);
    _hover.value = null;
    _menu = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        width: _itemWidth,
        // The finger that opened the menu keeps control, so the menu itself ignores touches.
        // Material gives the text a style; without it the menu text is drawn underlined.
        child: Material(
          type: MaterialType.transparency,
          child: IgnorePointer(
            child: ValueListenableBuilder<Mode?>(
              valueListenable: _hover,
              builder: (context, hovered, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < others.length; i++) ...[
                    if (i > 0) const SizedBox(height: _gap),
                    _MenuItem(
                      key: _itemKeys[others[i]],
                      mode: others[i],
                      hovered: hovered == others[i],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_menu!);
    if (Settings.instance.haptic) HapticFeedback.mediumImpact();
  }

  void _closeMenu() {
    _menu?.remove();
    _menu?.dispose();
    _menu = null;
    _hover.value = null;
  }

  @override
  void dispose() {
    _singleTap?.cancel();
    _timer?.cancel();
    _closeMenu();
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mode;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: Container(
        height: 40,
        constraints: BoxConstraints(minWidth: widget.showLabel ? 0 : 40),
        padding: EdgeInsets.symmetric(horizontal: widget.showLabel ? 14 : 0),
        decoration: BoxDecoration(
          color: context.desk.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(m.icon, size: 20, color: Colors.black),
            if (widget.showLabel) ...[
              const SizedBox(width: 8),
              Text(
                m.label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final Mode mode;
  final bool hovered;
  const _MenuItem({super.key, required this.mode, required this.hovered});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      height: _ModeButtonState._itemHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: hovered ? context.desk.accent : context.desk.key,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: hovered ? Colors.white : Colors.white24),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),
      child: Row(
        children: [
          Icon(
            mode.icon,
            size: 22,
            color: hovered ? Colors.black : Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                mode.label,
                style: TextStyle(
                  color: hovered ? Colors.black : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
