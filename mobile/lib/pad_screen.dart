import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'connection.dart';
import 'edge_zones.dart';
import 'mouse_widgets.dart';
import 'motion_cursor.dart';
import 'phone_media.dart';
import 'now_playing.dart';
import 'settings.dart';

/// Laptop-style touchpad: a large touch zone, left/right buttons underneath
/// and an on/off switch in the top-left corner.
class PadScreen extends StatefulWidget {
  const PadScreen({super.key});

  @override
  State<PadScreen> createState() => _PadScreenState();
}

class _PadScreenState extends State<PadScreen> {
  bool _phoneMedia = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) {
        final buttons = Settings.instance.padButtons;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          child: Container(
            decoration: BoxDecoration(
              color: context.desk.body,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: TouchPad(
                          enabled: Settings.instance.padEnabled,
                          phoneMedia:
                              _phoneMedia &&
                              Settings.instance.padPhoneMediaButton,
                        ),
                      ),
                      if (Settings.instance.padPhoneMediaButton)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: IconButton(
                            tooltip: _phoneMedia
                                ? 'Mobile media on'
                                : 'Mobile media off',
                            icon: Icon(
                              Icons.smartphone,
                              color: _phoneMedia
                                  ? context.desk.accent
                                  : Colors.white54,
                            ),
                            onPressed: () =>
                                setState(() => _phoneMedia = !_phoneMedia),
                          ),
                        ),
                    ],
                  ),
                ),
                // A slim bar, like the buttons under a laptop touchpad. Off in Settings: the
                // pad fills the whole area (tap clicks, a two-finger tap right-clicks).
                if (buttons) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: padButtonBarHeight,
                    child: Row(
                      children: const [
                        Expanded(
                          child: MouseButton(
                            label: 'LEFT',
                            button: 0,
                            compact: true,
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: MouseButton(
                            label: 'RIGHT',
                            button: 1,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Height of the Left / Right bar under the touchpad.
const padButtonBarHeight = 40.0;

enum _TwoFinger { undecided, scroll, zoom }

class TouchPad extends StatefulWidget {
  final bool enabled;
  final bool phoneMedia;
  final bool compact;
  const TouchPad({
    super.key,
    required this.enabled,
    this.phoneMedia = false,
    this.compact = false,
  });

  @override
  State<TouchPad> createState() => _TouchPadState();
}

class _TouchPadState extends State<TouchPad> {
  static const _tapMs = 220;
  static const _tapSlop = 12.0;
  static const _dragWindowMs = 280;
  static const _scrollStepPx = 16.0;
  static const _zoomStepPx = 28.0;
  static const _swipeMinPx = 70.0;

  /// A two-finger swipe goes Back / Forward from this far, and when it is mostly sideways.
  static const navMinPx = 80.0;
  static const _alt2 = 0xE2, _leftKey = 0x50, _rightKey = 0x4F;
  static const _ctrl = 0xE0, _alt = 0xE2, _super = 0xE3;
  static const _left = 0x50, _right = 0x4F;
  static const _printScreen = 0x46;

  final Map<int, Offset> _pos = {};
  DateTime _gestureStart = DateTime.now();
  double _travel = 0;
  int _maxFingers = 0;
  DateTime? _lastTapUp;
  bool _dragging = false;
  double _remX = 0, _remY = 0;
  double _scrollAccX = 0, _scrollAccY = 0, _zoomAcc = 0;

  _TwoFinger _two = _TwoFinger.undecided;
  double _panTotal = 0, _zoomTotal = 0;
  // Scroll or zoom is decided from where the fingers are once BOTH have moved: judged after
  // one finger's move alone, two fingers panning side by side look like a pinch.
  final Set<int> _movedSince = {};
  double _spreadMark = 0;
  double _navDx = 0,
      _navDy = 0; // how far two fingers went (for Back / Forward)

  Offset? _swipeStart, _swipeLast;
  bool _swiped = false;

  // Edge control zones: the zone the current single-finger touch started in, and how far
  // the finger has slid along it since the last step.
  EdgeZone _zone = EdgeZone.none;
  bool _onPlayPause =
      false; // the touch began on the play / pause icon in the top strip
  bool _onVolume = false; // the touch began on the volume strip: a tap mutes
  int _skip = 0; // ... or on the next (+1) / previous (-1) track button
  double _zoneAcc = 0;
  String? _hud; // what the last step did, shown briefly
  Timer? _hudTimer;
  EdgeZone? _hudZone; // set while the message shows a volume / brightness level
  bool _muted = false; // the volume strip shows a crossed-out speaker
  bool _playing = false; // the play / pause icon shows what a tap does next

  // Holding a finger on the << or >> end of the top strip keeps seeking.
  Timer? _holdTimer, _repeatTimer;
  static const _holdMs = 350;
  static const _holdSlop = 24.0; // a held finger wobbles a little

  Offset _centroid() {
    var c = Offset.zero;
    for (final p in _pos.values) {
      c += p;
    }
    return c / _pos.length.toDouble();
  }

  void _down(PointerDownEvent e) {
    if (_pos.isEmpty) {
      // A single finger starting in an edge strip controls volume / brightness / tracks.
      final size = context.size;
      _zone = Settings.instance.padZones && size != null
          ? EdgeZones.at(e.localPosition, size)
          : EdgeZone.none;
      if (_zone == EdgeZone.windows && !Settings.instance.padWindows) {
        _zone = EdgeZone.none;
      }
      _zoneAcc = 0;
      _endWindowSwitch();
      if (_zone == EdgeZone.windows) {
        // Held still: open the window switcher and keep it open while the finger is down.
        _winTimer = Timer(const Duration(milliseconds: _holdMs), () {
          if (_pos.length == 1 && _travel < _holdSlop && _modKey == null) {
            _windowStep(true);
          }
        });
      }
      _onPlayPause =
          _zone == EdgeZone.media &&
          EdgeZones.isPlayPause(e.localPosition, size!);
      _onVolume = _zone == EdgeZone.volume;
      _onSwitchToggle =
          _zone == EdgeZone.windows &&
          Settings.instance.padTabSwitch &&
          EdgeZones.isSwitchToggle(e.localPosition, size!);
      _skip = _zone == EdgeZone.media
          ? EdgeZones.skipButton(e.localPosition, size!)
          : 0;
      _stopHold();
      if (_zone == EdgeZone.media && !_onPlayPause && _skip == 0) {
        final forward = e.localPosition.dx > size!.width / 2;
        _holdTimer = Timer(const Duration(milliseconds: _holdMs), () {
          if (_pos.length == 1 && _travel < _holdSlop) _startRepeat(forward);
        });
      }
    } else {
      _zone = EdgeZone.none; // a second finger: ordinary multi-touch gestures
      _endWindowSwitch();
      _stopHold();
    }
    if (_pos.isEmpty) {
      _gestureStart = DateTime.now();
      _travel = 0;
      _maxFingers = 0;
      _scrollAccX = _scrollAccY = _zoomAcc = 0;
      _two = _TwoFinger.undecided;
      _panTotal = _zoomTotal = 0;
      _navDx = _navDy = 0;
      _swiped = false;
      _swipeStart = null;
      final lt = _lastTapUp;
      if (lt != null &&
          _zone == EdgeZone.none &&
          Settings.instance.tapToClick &&
          DateTime.now().difference(lt).inMilliseconds < _dragWindowMs) {
        _dragging = true;
        Connection.instance.button(0, true);
      }
    }
    _pos[e.pointer] = e.localPosition;
    _maxFingers = math.max(_maxFingers, _pos.length);
    if (_pos.length == 2) {
      _spreadMark = _spread();
      _movedSince.clear();
    }
    if (_pos.length == 3) {
      _swipeStart = _swipeLast = _centroid();
    }
    setState(() {});
  }

  void _move(PointerMoveEvent e) {
    final old = _pos[e.pointer];
    if (old == null) return;
    final delta = e.localPosition - old;
    final s = Settings.instance;
    final dBefore = _pos.length == 2 ? _spread() : 0.0;
    _pos[e.pointer] = e.localPosition;
    _travel += delta.distance;

    if (_pos.length == 1 && _zone != EdgeZone.none) {
      if (_travel >= _holdSlop) _stopHold(); // sliding, not holding
      _zoneMove(delta); // sliding along an edge: no cursor movement
    } else if (_pos.length == 1) {
      // Pointer acceleration: faster swipes travel further.
      final gain = s.pointerSpeed * (1 + math.min(delta.distance / 12, 2.0));
      _remX += delta.dx * gain;
      _remY += delta.dy * gain;
      final ix = _remX.truncate(), iy = _remY.truncate();
      if (ix != 0 || iy != 0) {
        _remX -= ix;
        _remY -= iy;
        Connection.instance.move(ix, iy);
      }
    } else if (_pos.length == 2) {
      final zoomDelta = _spread() - dBefore;
      final pan = delta / 2;
      _panTotal += pan.distance;
      _movedSince.add(e.pointer);
      if (_movedSince.length >= 2) {
        _movedSince.clear();
        final spread = _spread();
        _zoomTotal += (spread - _spreadMark).abs();
        _spreadMark = spread;
        if (_two == _TwoFinger.undecided &&
            (_panTotal > 10 || _zoomTotal > 10)) {
          _two = _zoomTotal > _panTotal * 1.2
              ? _TwoFinger.zoom
              : _TwoFinger.scroll;
        }
      }
      if (_two == _TwoFinger.scroll) {
        _navDx += pan.dx;
        _navDy += pan.dy;
        // With Back / Forward on, sideways movement is the swipe, not a scroll.
        _scrollAccX += s.padSwipeNav ? 0 : pan.dx;
        _scrollAccY += pan.dy;
        final sx = (_scrollAccX / _scrollStepPx).truncate();
        final sy = (_scrollAccY / _scrollStepPx).truncate();
        if (sx != 0 || sy != 0) {
          _scrollAccX -= sx * _scrollStepPx;
          _scrollAccY -= sy * _scrollStepPx;
          final k = s.naturalScroll ? 1 : -1;
          // Horizontal: natural = content follows the fingers (wheel -).
          Connection.instance.scroll(-sx * k, sy * k);
        }
      } else if (_two == _TwoFinger.zoom) {
        _zoomAcc += zoomDelta;
        final z = (_zoomAcc / _zoomStepPx).truncate();
        if (z != 0) {
          _zoomAcc -= z * _zoomStepPx;
          // Ctrl + wheel = zoom in most apps.
          Connection.instance.key(_ctrl, true);
          Connection.instance.scroll(0, z);
          Connection.instance.key(_ctrl, false);
        }
      }
    } else if (_pos.length == 3) {
      _swipeLast = _centroid();
    }
  }

  double _spread() {
    final it = _pos.values.iterator..moveNext();
    final a = it.current;
    it.moveNext();
    return (a - it.current).distance;
  }

  /// Sliding along an edge strip: one key press per [EdgeZones.stepPx] of travel.
  void _zoneMove(Offset delta) {
    if (_zone == EdgeZone.windows) {
      _winTimer?.cancel();
      _zoneAcc += EdgeZones.along(_zone, delta);
      final n = (_zoneAcc / EdgeZones.windowStepPx).truncate();
      if (n == 0) return;
      _zoneAcc -= n * EdgeZones.windowStepPx;
      for (var i = 0; i < math.min(n.abs(), 6); i++) {
        _windowStep(n > 0);
      }
      return;
    }
    final top = parseTopEdgeMode(Settings.instance.padTopMode);
    _zoneAcc += EdgeZones.along(_zone, delta);
    final step = EdgeZones.stepPx(_zone, top, Settings.instance.seekSpeed);
    final steps = (_zoneAcc / step).truncate();
    if (steps == 0) return;
    _zoneAcc -= steps * step;
    final positive = steps > 0;
    final hid = EdgeZones.key(_zone, positive: positive, top: top);
    if (_zone == EdgeZone.volume && _muted)
      setState(() => _muted = false); // volume keys unmute
    for (var i = 0; i < math.min(steps.abs(), 6); i++) {
      if (widget.phoneMedia) {
        _phoneEdge(_zone, positive, top);
      } else {
        Connection.instance.key(hid, true);
        Connection.instance.key(hid, false);
      }
      if (Settings.instance.haptic) HapticFeedback.selectionClick();
    }
    if (!widget.phoneMedia || _zone == EdgeZone.media) {
      _showHud(
        EdgeZones.label(_zone, positive: positive, top: top),
        zone: _zone,
      );
    }
  }

  int _phoneLevelSerial = 0;

  Future<void> _phoneEdge(EdgeZone zone, bool positive, TopEdgeMode top) async {
    final serial = ++_phoneLevelSerial;
    try {
      int? percent;
      switch (zone) {
        case EdgeZone.volume:
          percent = await PhoneMedia.volume(positive ? 1 : -1);
        case EdgeZone.brightness:
          percent = await PhoneMedia.brightness(positive ? 1 : -1);
        case EdgeZone.media:
          await PhoneMedia.action(
            top == TopEdgeMode.track
                ? (positive ? 'next' : 'previous')
                : (positive ? 'forward' : 'backward'),
          );
        default:
          break;
      }
      if (percent != null &&
          mounted &&
          widget.phoneMedia &&
          serial == _phoneLevelSerial) {
        _showHud(
          '${zone == EdgeZone.volume ? 'Phone volume' : 'Phone brightness'} $percent%',
        );
      }
    } catch (_) {
      if (mounted && widget.phoneMedia && serial == _phoneLevelSerial) {
        _showHud('Phone control unavailable');
      }
    }
  }

  // The window switcher on the bottom edge: Alt stays down while the finger is on the strip,
  // each step presses Tab (or Shift+Tab going back); lifting the finger releases Alt, which
  // switches to the chosen window.
  int? _modKey; // Alt (windows) or Ctrl (browser tabs), held while the finger is down
  bool _onSwitchToggle = false; // the touch began on the strip's centre icon
  Timer? _winTimer;
  static const _tab = 0x2B, _shift = 0xE1;

  void _windowStep(bool forward) {
    final c = Connection.instance;
    final tabs = Settings.instance.tabsMode;
    SwitchGuard.touch();
    if (_modKey == null) {
      _modKey = tabs ? _ctrl : _alt;
      c.key(_modKey!, true);
    }
    if (!forward) c.key(_shift, true);
    c.key(_tab, true);
    c.key(_tab, false);
    if (!forward) c.key(_shift, false);
    if (Settings.instance.haptic) HapticFeedback.selectionClick();
    _showHud(
      tabs
          ? (forward ? 'Next tab' : 'Previous tab')
          : (forward ? 'Next window' : 'Previous window'),
    );
  }

  void _endWindowSwitch() {
    _winTimer?.cancel();
    _winTimer = null;
    final held = _modKey;
    // The focus changes just after the last step.
    if (held != null) SwitchGuard.touch();
    if (held != null) {
      _modKey = null;
      Connection.instance.key(held, false);
    }
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _repeatTimer?.cancel();
    _holdTimer = _repeatTimer = null;
  }

  /// Keep sending forward / backward (or next / previous) while the finger stays down.
  void _startRepeat(bool forward) {
    final top = parseTopEdgeMode(Settings.instance.padTopMode);
    final hid = EdgeZones.key(EdgeZone.media, positive: forward, top: top);
    final label = EdgeZones.label(EdgeZone.media, positive: forward, top: top);
    void step() {
      if (widget.phoneMedia) {
        _phoneEdge(EdgeZone.media, forward, top);
      } else {
        Connection.instance.key(hid, true);
        Connection.instance.key(hid, false);
      }
      if (Settings.instance.haptic) HapticFeedback.selectionClick();
      _showHud(label);
    }

    step();
    _repeatTimer = Timer.periodic(
      EdgeZones.repeatEvery(Settings.instance.seekSpeed),
      (_) => step(),
    );
  }

  void _showHud(String text, {EdgeZone? zone}) {
    _hudTimer?.cancel();
    setState(() {
      _hud = text;
      _hudZone = zone;
    });
    _hudTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  /// The message with the computer's real percentage when it is known.
  String _hudText() {
    if (widget.phoneMedia) return _hud ?? '';
    final c = Connection.instance;
    switch (_hudZone) {
      case EdgeZone.volume:
        if (c.muted) return 'Volume muted';
        if (c.volumePct != null) return 'Volume ${c.volumePct}%';
      case EdgeZone.brightness:
        if (c.brightnessUnsupported)
          return 'Brightness not supported on this computer';
        if (c.brightnessPct != null) return 'Brightness ${c.brightnessPct}%';
      default:
    }
    return _hud ?? '';
  }

  /// A new level arrived: keep the message up a little longer and show the number.
  void _levelsChanged() {
    if (!mounted) return;
    final c = Connection.instance;
    // The computer says whether it is muted: believe it over our own guess.
    if (!widget.phoneMedia && c.levelsKnown && c.muted != _muted) {
      setState(() => _muted = c.muted);
    }
    if (_hud != null && _hudZone != null) _showHud(_hud!, zone: _hudZone);
  }

  @override
  void initState() {
    super.initState();
    Connection.instance.addListener(_levelsChanged);
    Settings.instance.addListener(_syncMotion);
    _syncMotion();
  }

  @override
  void didUpdateWidget(TouchPad old) {
    super.didUpdateWidget(old);
    _syncMotion();
  }

  // ---- phone motion moves the cursor (Settings > Touchpad) ----------------------------------

  final _motion = MotionCursor();
  StreamSubscription<AccelerometerEvent>? _accSub;
  DateTime? _accAt;
  bool _clutch = false;
  double _motionRemX = 0, _motionRemY = 0;

  /// The sensor runs only while the setting is on and the pad is on.
  void _syncMotion() {
    final want = Settings.instance.padMotion && widget.enabled;
    if (want && _accSub == null) {
      _accSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onAccel, onError: (_) {});
    } else if (!want && _accSub != null) {
      _stopMotion();
    }
  }

  void _stopMotion() {
    _accSub?.cancel();
    _accSub = null;
    _accAt = null;
    _clutch = false;
    _motion.release();
    _motionRemX = _motionRemY = 0;
  }

  /// Tilt joystick, like the Mouse screen: by default one finger resting on the pad is the
  /// clutch (the pose when it touched is "centre"; tilt from there and the cursor moves; lift
  /// the finger and nothing moves). With "also without touching" the phone moves the cursor all
  /// the time (a held tilt fades away), and a finger moves it too, at the same moment.
  void _onAccel(AccelerometerEvent e) {
    _motion.gravity(e.x, e.y, e.z);
    final prev = _accAt;
    _accAt = e.timestamp;
    final s = Settings.instance;
    final always = s.padMotionAlways;
    final on =
        widget.enabled &&
        (always || (_pos.length == 1 && _zone == EdgeZone.none));
    if (!on) {
      _clutch = false;
      _motion.release();
      return;
    }
    if (!_clutch || !_motion.engaged) {
      _clutch = _motion.engage(); // the pose now is "centre"
      return;
    }
    if (prev == null) return;
    final dt = e.timestamp.difference(prev).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.1) return;
    final m = _motion.move(
      dt,
      speed: s.padMotionSpeed,
      invert: s.padMotionInvert,
      follow: always,
    );
    if (m == null) return;
    _motionRemX += m.dx;
    _motionRemY += m.dy;
    final ix = _motionRemX.truncate(), iy = _motionRemY.truncate();
    if (ix == 0 && iy == 0) return;
    _motionRemX -= ix;
    _motionRemY -= iy;
    _travel += (ix.abs() + iy.abs()).toDouble(); // moved by motion: not a tap
    Connection.instance.move(ix, iy);
  }

  void _threeFingerSwipe() {
    final a = _swipeStart, b = _swipeLast;
    if (a == null || b == null || _swiped) return;
    final d = b - a;
    if (d.distance < _swipeMinPx) return;
    _swiped = true;
    final c = Connection.instance;
    if (d.dx.abs() > d.dy.abs()) {
      // Switch workspace.
      c.chord([_ctrl, _alt], d.dx > 0 ? _left : _right);
    } else if (d.dy < 0) {
      c.chord([], _super); // overview
    } else if (Settings.instance.screenshotSwipe) {
      // Swipe down with three fingers: screenshot on the computer.
      c.chord([], _printScreen);
      _screenshotFeedback();
    }
  }

  void _screenshotFeedback() {
    if (Settings.instance.haptic) HapticFeedback.mediumImpact();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Screenshot taken on the computer'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          width: 280,
        ),
      );
  }

  /// Two fingers swiped sideways (the first finger is just being lifted): right to left = Back,
  /// left to right = Forward.
  void _twoFingerSwipe() {
    if (!Settings.instance.padSwipeNav || _maxFingers != 2 || _swiped) return;
    if (_two == _TwoFinger.zoom) return;
    if (_navDx.abs() < navMinPx || _navDx.abs() < _navDy.abs() * 2) return;
    _swiped = true; // not a tap either
    final back = _navDx < 0;
    Connection.instance.chord([_alt2], back ? _leftKey : _rightKey);
    if (Settings.instance.haptic) HapticFeedback.selectionClick();
    _showHud(back ? 'Back' : 'Forward');
  }

  void _up(PointerEvent e) {
    if (!_pos.containsKey(e.pointer)) return;
    if (_pos.length == 3) _threeFingerSwipe();
    if (_pos.length == 2) _twoFingerSwipe();
    _pos.remove(e.pointer);
    _stopHold();
    _endWindowSwitch();
    if (_pos.isEmpty) {
      final onPlayPause = _onPlayPause;
      final skip = _skip;
      final onVolume = _onVolume;
      final onToggle = _onSwitchToggle;
      _onVolume = false;
      _onSwitchToggle = false;
      _zone = EdgeZone.none;
      _onPlayPause = false;
      _skip = 0;
      final ms = DateTime.now().difference(_gestureStart).inMilliseconds;
      final wasTap = ms < _tapMs && _travel < _tapSlop;
      if (_dragging) {
        Connection.instance.button(0, false);
        _dragging = false;
        _lastTapUp = null;
      } else if (wasTap && onPlayPause && _maxFingers == 1) {
        // A tap on the play / pause icon (not a click).
        if (widget.phoneMedia) {
          PhoneMedia.action('playPause');
        } else {
          Connection.instance.key(EdgeZones.playPauseKey, true);
          Connection.instance.key(EdgeZones.playPauseKey, false);
        }
        if (Settings.instance.haptic) HapticFeedback.selectionClick();
        _playing = !_playing;
        _showHud(_playing ? 'Play' : 'Pause');
      } else if (wasTap && onToggle && _maxFingers == 1) {
        // A tap on the bottom strip's centre icon: switch windows <-> browser tabs.
        Settings.instance.update(
          () => Settings.instance.switchTabs = !Settings.instance.switchTabs,
        );
        if (Settings.instance.haptic) HapticFeedback.selectionClick();
        _showHud(
          Settings.instance.tabsMode
              ? 'Switching browser tabs'
              : 'Switching windows',
        );
      } else if (wasTap && onVolume && _maxFingers == 1) {
        // A tap on the volume strip: mute / unmute.
        if (widget.phoneMedia) {
          PhoneMedia.mute();
        } else {
          Connection.instance.key(EdgeZones.muteKey, true);
          Connection.instance.key(EdgeZones.muteKey, false);
        }
        if (Settings.instance.haptic) HapticFeedback.selectionClick();
        setState(() => _muted = !_muted);
        _showHud(_muted ? 'Muted' : 'Unmuted');
      } else if (wasTap && skip != 0 && _maxFingers == 1) {
        // A tap on the next / previous track button.
        final key = skip > 0 ? EdgeZones.nextKey : EdgeZones.previousKey;
        if (widget.phoneMedia) {
          PhoneMedia.action(skip > 0 ? 'next' : 'previous');
        } else {
          Connection.instance.key(key, true);
          Connection.instance.key(key, false);
        }
        if (Settings.instance.haptic) HapticFeedback.selectionClick();
        _showHud(skip > 0 ? 'Next track' : 'Previous track');
      } else if (wasTap && Settings.instance.tapToClick && !_swiped) {
        switch (_maxFingers) {
          case 1:
            Connection.instance.click(0);
            _lastTapUp = DateTime.now();
          case 2:
            Connection.instance.click(1);
          default:
            Connection.instance.click(2);
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    Settings.instance.removeListener(_syncMotion);
    _stopMotion();
    Connection.instance.removeListener(_levelsChanged);
    _endWindowSwitch();
    _hudTimer?.cancel();
    _stopHold();
    if (_dragging) Connection.instance.button(0, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _pos.isNotEmpty;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: !widget.enabled,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: Container(
                decoration: BoxDecoration(
                  color: !widget.enabled
                      ? context.desk.padOff
                      : active
                      ? context.desk.padActive
                      : context.desk.pad,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ListenableBuilder(
                      listenable: Connection.instance,
                      builder: (context, _) {
                        final hasMedia =
                            widget.enabled &&
                            Settings.instance.padZones &&
                            !widget.phoneMedia &&
                            Connection.instance.active?.effective != null &&
                            (Connection
                                    .instance
                                    .active
                                    ?.nowPlaying
                                    .title
                                    .isNotEmpty ??
                                false);
                        final hint = Center(
                          child: Text(
                            widget.enabled
                                ? widget.compact
                                      ? 'Drag: move · tap: click\n'
                                            '2 fingers: scroll · pinch: zoom\n'
                                            'Edges: media, volume, brightness'
                                      : '1 finger: move · tap: click · tap + drag: drag\n'
                                            '2 fingers: scroll · pinch: zoom · tap: right click${Settings.instance.padSwipeNav ? ' · swipe sideways = back / forward' : ''}\n'
                                            '3 fingers: tap = middle click · swipe left / right = workspace\n'
                                            'swipe up = overview${Settings.instance.screenshotSwipe ? ' · swipe down = screenshot' : ''}'
                                            '${Settings.instance.padMotion ? (Settings.instance.padMotionAlways ? '\ntilt the phone: the cursor follows (a finger works too)' : '\nhold a finger and tilt the phone: the cursor follows') : ''}'
                                : 'Touchpad off',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 12,
                              height: 1.7,
                            ),
                          ),
                        );
                        if (!hasMedia) return hint;
                        final hasTimeline =
                            (Connection
                                .instance
                                .active
                                ?.nowPlaying
                                .hasTimeline ??
                            false);
                        if (hasTimeline && box.maxHeight < 210) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: EdgeInsets.only(
                            top: hasTimeline ? 80 : 64,
                            bottom: 40,
                          ),
                          child: FittedBox(fit: BoxFit.scaleDown, child: hint),
                        );
                      },
                    ),
                    if (widget.enabled && Settings.instance.padZones)
                      ListenableBuilder(
                        listenable: Connection.instance,
                        builder: (context, _) {
                          final session = Connection.instance.active;
                          final media =
                              widget.phoneMedia || session?.effective == null
                              ? const NowPlaying()
                              : session!.nowPlaying;
                          return EdgeZoneMarks(
                            media: media,
                            integratedMedia:
                                media.hasTimeline && box.maxHeight >= 150,
                            top: parseTopEdgeMode(Settings.instance.padTopMode),
                            playing: media.title.isEmpty
                                ? _playing
                                : media.playing,
                            muted: _muted,
                            windows: Settings.instance.padWindows,
                            tabs: Settings.instance.tabsMode,
                          );
                        },
                      ),
                    // What the last slide on an edge did (volume, brightness, track).
                    if (_hud != null)
                      Positioned(
                        top: EdgeZones.edge + 8,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xCC00D4BE),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListenableBuilder(
                                listenable: Connection.instance,
                                builder: (_, _) => Text(
                                  _hudText(),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.enabled &&
              Settings.instance.padZones &&
              !widget.phoneMedia &&
              box.maxHeight >= 150)
            ListenableBuilder(
              listenable: Connection.instance,
              builder: (context, _) {
                final session = Connection.instance.active;
                final media = session?.effective == null
                    ? const NowPlaying()
                    : session!.nowPlaying;
                if (media.title.isEmpty || !media.hasTimeline) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: box.maxWidth * .2,
                  right: box.maxWidth * .2,
                  top: 0,
                  height: 56,
                  child: MediaTimeline(
                    media: media,
                    onAction: (action) {
                      if (Connection.instance.activeId != session!.device.id) {
                        return;
                      }
                      final key = switch (action) {
                        'previous' => EdgeZones.previousKey,
                        'next' => EdgeZones.nextKey,
                        _ => EdgeZones.playPauseKey,
                      };
                      Connection.instance.key(key, true);
                      Connection.instance.key(key, false);
                    },
                    onSeek: (key, position) => Connection.instance.seekMedia(
                      session!.device.id,
                      key,
                      position,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
