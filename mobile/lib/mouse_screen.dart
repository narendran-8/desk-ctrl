import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'connection.dart';
import 'settings.dart';

const _outline = Color(0xFFE6E8EC);

/// A mouse drawn like a real one: left/right buttons on top, wheel in the
/// middle, body below. Hold the body and tilt/rotate the phone to move the
/// cursor (a finger drag on the body works too).
class MouseScreen extends StatefulWidget {
  const MouseScreen({super.key});

  @override
  State<MouseScreen> createState() => _MouseScreenState();
}

class _MouseScreenState extends State<MouseScreen> {
  StreamSubscription<AccelerometerEvent>? _sub;
  final Set<int> _aiming = {};
  DateTime? _last;
  double _remX = 0, _remY = 0;
  bool _noSensor = false;
  static bool _lastPortrait = true;
  bool _portrait = _lastPortrait;

  // Low-passed gravity vector and the pose captured when the body is touched.
  double _gx = 0, _gy = 0, _gz = 9.8;
  bool _haveGravity = false;
  double _roll0 = 0, _pitch0 = 0;

  @override
  void initState() {
    super.initState();
    _applyOrientation();
    _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
        .listen(_onAccel, onError: (_) => setState(() => _noSensor = true));
  }

  // Gravity expressed in screen axes (x right, y up the screen), so tilt
  // feels the same in portrait and landscape.
  double get _sx => _portrait ? _gx : -_gy;
  double get _sy => _portrait ? _gy : _gx;

  double get _roll => math.atan2(_sx, math.sqrt(_sy * _sy + _gz * _gz));
  double get _pitch => math.atan2(_sy, _gz);

  void _applyOrientation() {
    SystemChrome.setPreferredOrientations([
      _portrait
          ? DeviceOrientation.portraitUp
          : DeviceOrientation.landscapeLeft,
    ]);
  }

  void _toggleOrientation() {
    _lastPortrait = !_portrait;
    setState(() => _portrait = _lastPortrait);
    _applyOrientation();
  }

  void _emit(double dx, double dy) {
    _remX += dx;
    _remY += dy;
    final ix = _remX.truncate(), iy = _remY.truncate();
    if (ix != 0 || iy != 0) {
      _remX -= ix;
      _remY -= iy;
      Connection.instance.move(ix, iy);
    }
  }

  /// Tilt-as-joystick: the further the phone is tilted from the pose it had
  /// when you touched the body, the faster the cursor moves that way.
  void _onAccel(AccelerometerEvent e) {
    const a = 0.25;
    if (!_haveGravity) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
      _haveGravity = true;
    } else {
      _gx += a * (e.x - _gx);
      _gy += a * (e.y - _gy);
      _gz += a * (e.z - _gz);
    }
    final now = DateTime.now();
    final prev = _last;
    _last = now;
    if (prev == null || _aiming.isEmpty) return;
    final dt = now.difference(prev).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.1) return;

    final s = Settings.instance;
    final sign = s.invertGyro ? -1.0 : 1.0;
    var dRoll = _roll - _roll0;
    var dPitch = _pitch - _pitch0;
    if (dPitch > math.pi) dPitch -= 2 * math.pi;
    if (dPitch < -math.pi) dPitch += 2 * math.pi;

    const dead = 0.05; // ~3 degrees
    double curve(double v) {
      final ex = v.abs() - dead;
      if (ex <= 0) return 0;
      return v.sign * ex * (1 + 3 * ex);
    }

    // Tilt right -> cursor right; tilt top edge down -> cursor up.
    final vx = curve(dRoll) * sign;
    final vy = curve(dPitch) * sign;
    final k = s.gyroSpeed * 2.5;
    _emit(vx * k * dt, vy * k * dt);
  }

  @override
  void dispose() {
    _sub?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _bodyDown(PointerDownEvent e) {
    if (_aiming.isEmpty) {
      _roll0 = _roll;
      _pitch0 = _pitch;
      _last = DateTime.now();
    }
    setState(() => _aiming.add(e.pointer));
  }

  void _bodyMove(PointerMoveEvent e) {
    // Finger drag also moves the cursor.
    final g = Settings.instance.pointerSpeed;
    _emit(e.delta.dx * g, e.delta.dy * g);
  }

  void _bodyEnd(PointerEvent e) {
    if (_aiming.remove(e.pointer)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final aiming = _aiming.isNotEmpty;
    return LayoutBuilder(
      builder: (context, box) {
        var w = box.maxWidth - 24;
        var h = w / 0.62;
        if (h > box.maxHeight - 12) {
          h = box.maxHeight - 12;
          w = h * 0.62;
        }
        return Stack(
          children: [
            Center(child: _buildMouse(w, h, aiming)),
            Positioned(
              right: 8,
              top: 4,
              child: IconButton.filledTonal(
                tooltip: 'Rotate',
                icon: Icon(
                  _portrait
                      ? Icons.stay_current_landscape
                      : Icons.stay_current_portrait,
                ),
                onPressed: _toggleOrientation,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMouse(double w, double h, bool aiming) {
    final topH = h * 0.385;
    final shape = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w / 2),
    );
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          ClipPath(
            clipper: _ShapeClipper(shape),
            child: Column(
              children: [
                SizedBox(
                  height: topH,
                  child: Row(
                    children: const [
                      Expanded(child: _ZoneButton(button: 0)),
                      Expanded(child: _ZoneButton(button: 1)),
                    ],
                  ),
                ),
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _bodyDown,
                    onPointerMove: _bodyMove,
                    onPointerUp: _bodyEnd,
                    onPointerCancel: _bodyEnd,
                    child: Container(
                      color: aiming ? context.desk.accentDim : context.desk.pad,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_with,
                            size: 40,
                            color: aiming ? Colors.white : Colors.white24,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _noSensor
                                ? 'No motion sensor.\nDrag a finger here.'
                                : aiming
                                ? 'Tilt the phone'
                                : 'Hold here and tilt\nthe phone (or drag)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: aiming ? Colors.white : Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Wheel
          Positioned(
            left: w * 0.43,
            top: h * 0.09,
            width: w * 0.145,
            height: h * 0.22,
            child: const _Wheel(),
          ),
          // Outline + divider lines drawn over the zones
          IgnorePointer(
            child: CustomPaint(
              size: Size(w, h),
              painter: _OutlinePainter(shape, topH),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShapeClipper extends CustomClipper<Path> {
  final RRect shape;
  _ShapeClipper(this.shape);
  @override
  Path getClip(Size size) => Path()..addRRect(shape);
  @override
  bool shouldReclip(covariant _ShapeClipper old) => old.shape != shape;
}

class _OutlinePainter extends CustomPainter {
  final RRect shape;
  final double topH;
  _OutlinePainter(this.shape, this.topH);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(shape, p);
    canvas.drawLine(Offset(0, topH), Offset(size.width, topH), p);
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height * 0.09),
      p,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.31),
      Offset(size.width / 2, topH),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _OutlinePainter old) => false;
}

/// Left (0) or right (1) mouse button zone; hold + move another finger = drag.
class _ZoneButton extends StatefulWidget {
  final int button;
  const _ZoneButton({required this.button});

  @override
  State<_ZoneButton> createState() => _ZoneButtonState();
}

class _ZoneButtonState extends State<_ZoneButton> {
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
        color: _pointer != null ? context.desk.accent : context.desk.key,
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          widget.button == 0 ? 'L' : 'R',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ),
    );
  }
}

/// Scroll wheel: drag up/down to scroll, tap for middle click.
class _Wheel extends StatefulWidget {
  const _Wheel();

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  static const _stepPx = 14.0;
  int? _pointer;
  double _acc = 0, _travel = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointer = e.pointer;
        _acc = _travel = 0;
        setState(() {});
      },
      onPointerMove: (e) {
        if (e.pointer != _pointer) return;
        _travel += e.delta.distance;
        _acc += e.delta.dy;
        final steps = (_acc / _stepPx).truncate();
        if (steps != 0) {
          _acc -= steps * _stepPx;
          final nat = Settings.instance.naturalScroll;
          Connection.instance.scroll(0, nat ? steps : -steps);
          if (Settings.instance.haptic) HapticFeedback.selectionClick();
        }
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        if (_travel < 8) Connection.instance.click(2);
        setState(() => _pointer = null);
      },
      onPointerCancel: (e) => setState(() => _pointer = null),
      child: Container(
        decoration: BoxDecoration(
          color: _pointer != null ? context.desk.accent : context.desk.keyAlt,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: _outline, width: 2.5),
        ),
      ),
    );
  }
}
