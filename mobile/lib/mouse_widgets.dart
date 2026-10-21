import 'package:flutter/material.dart';

import 'app_theme.dart';

import 'package:flutter/services.dart';

import 'connection.dart';
import 'settings.dart';

/// Hold-able mouse button (hold + move another finger = drag).
class MouseButton extends StatefulWidget {
  final String label;
  final int button; // 0 left, 1 right, 2 middle

  /// Slim, quiet styling for the bar under the touchpad.
  final bool compact;
  const MouseButton({
    super.key,
    required this.label,
    required this.button,
    this.compact = false,
  });

  @override
  State<MouseButton> createState() => _MouseButtonState();
}

class _MouseButtonState extends State<MouseButton> {
  int? _pointer;

  @override
  void dispose() {
    if (_pointer != null) Connection.instance.button(widget.button, false);
    super.dispose();
  }

  void _release(PointerEvent e) {
    if (e.pointer != _pointer) return;
    setState(() => _pointer = null);
    Connection.instance.button(widget.button, false);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pointer != null;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer != null) return;
        setState(() => _pointer = e.pointer);
        Connection.instance.button(widget.button, true);
        if (Settings.instance.haptic) HapticFeedback.lightImpact();
      },
      onPointerUp: _release,
      onPointerCancel: _release,
      child: Container(
        margin: EdgeInsets.all(widget.compact ? 0 : 3),
        decoration: BoxDecoration(
          color: pressed ? context.desk.accent : context.desk.keyAlt,
          borderRadius: BorderRadius.circular(widget.compact ? 12 : 10),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: widget.compact
              ? TextStyle(
                  color: pressed ? Colors.white : Colors.white70,
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                )
              : const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }
}

/// Vertical strip: drag up/down to scroll the wheel.
class ScrollStrip extends StatelessWidget {
  const ScrollStrip({super.key});

  static const _stepPx = 18.0;

  @override
  Widget build(BuildContext context) {
    double acc = 0;
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        acc += d.delta.dy;
        final steps = (acc / _stepPx).truncate();
        if (steps != 0) {
          acc -= steps * _stepPx;
          final nat = Settings.instance.naturalScroll;
          Connection.instance.scroll(0, nat ? steps : -steps);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: context.desk.key,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const RotatedBox(
          quarterTurns: 3,
          child: Text(
            '⇅  SCROLL',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// Right-hand column with all mouse buttons plus scroll.
class MouseButtonColumn extends StatelessWidget {
  const MouseButtonColumn({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(flex: 2, child: ScrollStrip()),
        Expanded(
          flex: 5,
          child: Column(
            children: const [
              Expanded(flex: 4, child: MouseButton(label: 'LEFT', button: 0)),
              Expanded(flex: 2, child: MouseButton(label: 'MIDDLE', button: 2)),
              Expanded(flex: 4, child: MouseButton(label: 'RIGHT', button: 1)),
            ],
          ),
        ),
      ],
    );
  }
}
