import 'dart:math' as math;

/// Moves the cursor by tilting the phone, from the accelerometer alone (every phone has one;
/// many cheaper ones have no gyroscope). It is the same joystick the Mouse screen has: the
/// further the phone is tilted from the pose it had when the clutch was engaged (a finger
/// touched the pad), the faster the cursor moves that way.
///  - lean the phone to the right  -> the cursor goes right
///  - tilt the top of the screen away from you -> the cursor goes up (towards you: down)
///
/// It works however the phone is held (portrait, either landscape): the direction of gravity
/// at the moment of [engage] tells which way "up the screen" is in the phone's own axes.
/// Phone axes (Android): x to the right of the screen, y up the screen, z out of the screen.
class MotionCursor {
  /// A little tilt (about 3 degrees) does nothing: a hand is never perfectly still.
  static const deadZone = 0.05;

  /// Seconds the resting pose takes to follow a held tilt in "always on" mode.
  static const followSeconds = 2.0;

  double _gx = 0, _gy = 0, _gz = 9.8;
  bool _haveGravity = false;

  // The screen's axes in the phone's x / y plane, taken from the pose at [engage].
  double _ux = 0, _uy = 1, _rx = 1, _ry = 0;
  double _roll0 = 0, _pitch0 = 0;
  bool _engaged = false;

  bool get engaged => _engaged;

  /// Feed the accelerometer (m/s^2); smoothed, because a moving phone also measures its movement.
  void gravity(double x, double y, double z) {
    if (!_haveGravity) {
      _gx = x;
      _gy = y;
      _gz = z;
      _haveGravity = true;
      return;
    }
    const a = 0.25;
    _gx += a * (x - _gx);
    _gy += a * (y - _gy);
    _gz += a * (z - _gz);
  }

  /// The current pose becomes "no movement". False when it cannot be told (no reading yet, or
  /// the phone lies (nearly) flat, where "up the screen" means nothing).
  bool engage() {
    _engaged = false;
    if (!_haveGravity) return false;
    final n = math.sqrt(_gx * _gx + _gy * _gy);
    if (n < 2.5) return false;
    _ux = _gx / n;
    _uy = _gy / n;
    _rx = _uy; // the screen's right: up x (out of the screen)
    _ry = -_ux;
    _roll0 = _roll;
    _pitch0 = _pitch;
    return _engaged = true;
  }

  void release() => _engaged = false;

  double get _sx => _gx * _rx + _gy * _ry; // gravity along the screen's right
  double get _sy => _gx * _ux + _gy * _uy; // ... and up the screen

  double get _roll => math.atan2(_sx, math.sqrt(_sy * _sy + _gz * _gz));
  double get _pitch => math.atan2(_sy, _gz);

  static double _curve(double v) {
    final ex = v.abs() - deadZone;
    if (ex <= 0) return 0;
    return v.sign * ex * (1 + 3 * ex);
  }

  /// The movement in pixels (dx right, dy down) over [dt] seconds, or null when not engaged.
  /// [speed] is the user's setting (200 - 2500, 900 normal). With [follow] the resting pose
  /// drifts to where the phone is held, so a tilt that is kept up fades after a few seconds
  /// and nothing needs a clutch.
  ({double dx, double dy})? move(
    double dt, {
    double speed = 900,
    bool invert = false,
    bool follow = false,
  }) {
    if (!_engaged || dt <= 0) return null;
    var dRoll = _roll - _roll0;
    var dPitch = _pitch - _pitch0;
    if (dPitch > math.pi) dPitch -= 2 * math.pi;
    if (dPitch < -math.pi) dPitch += 2 * math.pi;
    final k = speed * 2.5 * dt * (invert ? -1 : 1);
    final out = (dx: _curve(dRoll) * k, dy: _curve(dPitch) * k);
    if (follow) {
      final f = math.min(1.0, dt / followSeconds);
      _roll0 += dRoll * f;
      _pitch0 += dPitch * f;
    }
    return out;
  }
}
