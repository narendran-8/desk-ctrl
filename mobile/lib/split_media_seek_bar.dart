import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One timeline split around a separate play/pause control. Dragging can cross
/// the gap, but the playhead is always painted on a visible segment.
class SplitMediaSeekBar extends StatefulWidget {
  const SplitMediaSeekBar({
    super.key,
    required this.value,
    required this.max,
    required this.center,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onCancel,
  });
  final double value, max;
  final Widget center;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  final VoidCallback? onCancel;
  static const gap = 38.0;
  @override
  State<SplitMediaSeekBar> createState() => _SplitMediaSeekBarState();
}

class _SplitMediaSeekBarState extends State<SplitMediaSeekBar> {
  double? _drag;
  double _valueAt(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final x = box.globalToLocal(global).dx;
    final half = (box.size.width - SplitMediaSeekBar.gap) / 2;
    final inset = math.min(8.0, half / 3);
    final usable = math.max(1.0, half - inset * 2);
    if (x <= half) return ((x - inset) / usable).clamp(0, 1) * widget.max / 2;
    if (x < half + SplitMediaSeekBar.gap) return widget.max / 2;
    return (1 +
            ((x - half - SplitMediaSeekBar.gap - inset) / usable).clamp(0, 1)) *
        widget.max /
        2;
  }

  void _start(Offset global) {
    _drag = _valueAt(global);
    widget.onChangeStart?.call(_drag!);
    widget.onChanged?.call(_drag!);
  }

  void _finish() {
    if (_drag == null) return;
    final value = _drag!;
    _drag = null;
    widget.onChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Playback position',
    value: '${(widget.value / widget.max * 100).round()} percent',
    increasedValue:
        '${((widget.value + 5000).clamp(0, widget.max) / widget.max * 100).round()} percent',
    decreasedValue:
        '${((widget.value - 5000).clamp(0, widget.max) / widget.max * 100).round()} percent',
    explicitChildNodes: true,
    onIncrease: widget.onChanged == null ? null : () => _semanticStep(5000),
    onDecrease: widget.onChanged == null ? null : () => _semanticStep(-5000),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: widget.onChanged == null
          ? null
          : (event) {
              final box = context.findRenderObject()! as RenderBox;
              if ((event.localPosition.dx - box.size.width / 2).abs() <
                  SplitMediaSeekBar.gap / 2) {
                return;
              }
              _start(event.globalPosition);
              _finish();
            },
      onHorizontalDragStart: widget.onChanged == null
          ? null
          : (event) => _start(event.globalPosition),
      onHorizontalDragUpdate: widget.onChanged == null
          ? null
          : (event) {
              _drag = _valueAt(event.globalPosition);
              widget.onChanged?.call(_drag!);
            },
      onHorizontalDragEnd: widget.onChanged == null ? null : (_) => _finish(),
      onHorizontalDragCancel: () {
        _drag = null;
        widget.onCancel?.call();
      },
      child: CustomPaint(
        key: const Key('mediaSeekPaint'),
        painter: SplitSeekPainter(widget.value / widget.max),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const Expanded(
                child: SizedBox(key: Key('mediaSeekLeft'), height: 40),
              ),
              SizedBox(
                width: SplitMediaSeekBar.gap,
                child: Center(child: widget.center),
              ),
              const Expanded(
                child: SizedBox(key: Key('mediaSeekRight'), height: 40),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  void _semanticStep(double delta) {
    final value = (widget.value + delta).clamp(0.0, widget.max);
    widget.onChangeStart?.call(value);
    widget.onChanged?.call(value);
    widget.onChangeEnd?.call(value);
  }
}

class SplitSeekPainter extends CustomPainter {
  const SplitSeekPainter(this.progress);
  final double progress;
  static const played = Colors.red;
  static final remaining = Colors.grey.shade700;
  Offset thumbCenter(Size size) {
    final half = (size.width - SplitMediaSeekBar.gap) / 2;
    final inset = math.min(8.0, half / 3);
    final usable = math.max(1.0, half - inset * 2);
    final p = progress.clamp(0.0, 1.0);
    return Offset(
      p <= .5
          ? inset + usable * p * 2
          : half + SplitMediaSeekBar.gap + inset + usable * (p - .5) * 2,
      size.height / 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final half = (size.width - SplitMediaSeekBar.gap) / 2;
    final inset = math.min(8.0, half / 3);
    final usable = math.max(1.0, half - inset * 2);
    final y = size.height / 2;
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var side = 0; side < 2; side++) {
      final start = inset + side * (half + SplitMediaSeekBar.gap);
      paint.color = remaining;
      canvas.drawLine(Offset(start, y), Offset(start + usable, y), paint);
      final filled = (progress * 2 - side).clamp(0.0, 1.0);
      if (filled > 0) {
        paint.color = played;
        canvas.drawLine(
          Offset(start, y),
          Offset(start + usable * filled, y),
          paint,
        );
      }
    }
    canvas.drawCircle(thumbCenter(size), 5, Paint()..color = played);
  }

  @override
  bool shouldRepaint(SplitSeekPainter old) => old.progress != progress;
}
