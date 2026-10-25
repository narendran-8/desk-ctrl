import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_theme.dart';
import 'connection.dart';
import 'device_color.dart';
import 'edge_zones.dart';
import 'edit_menu.dart';
import 'devices_screen.dart';
import 'key_sound.dart';
import 'keyboard_screen.dart';
import 'mode_button.dart';
import 'modes.dart';
import 'mouse_screen.dart';
import 'mobile_screen.dart';
import 'notch_layout.dart';
import 'pad_screen.dart';
import 'remote_audio_sheet.dart';
import 'voice_screen.dart';
import 'settings.dart';
import 'settings_sheet.dart';
import 'usb_pairing.dart';
import 'window_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Settings.instance.load();
  // Draw into the notch area unless the user said never: the layout then keeps clear of the notch.
  WindowMode.useCutout(Settings.instance.notchBar != 'off');
  WakelockPlus.enable();
  KeySound.instance.init();
  await Connection.instance
      .dedupeAll(); // join entries that are the same computer
  Connection.instance.restoreLast(); // runs in the background
  UsbPairing.start(); // a phone plugged in is paired by the agent
  UsbPairing.watchCable(); // a cable pulled out drops the USB link at once
  runApp(const DeskCtrlApp());
}

class DeskCtrlApp extends StatelessWidget {
  const DeskCtrlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) => MaterialApp(
        title: 'ViL',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(Settings.instance),
        home: const Home(),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  /// The mode on screen. Starts on the first mode of the user's order.
  late Mode _mode;

  @override
  void initState() {
    super.initState();
    final st = Settings.instance;
    _mode = availableModes(
      mouse: st.mouseTab,
      pad: st.padTab,
      voice: st.voiceTab,
      mobile: st.mobileTab,
      order: st.modeOrderList,
    ).first;
    Connection.instance.onTextFocus = _textFocus;
    Connection.instance.onClick = _clicked;
    Connection.instance.onCopied = _copied;
  }

  Timer? _focusTimer, _clickTimer, _toastTimer;
  bool _toast = false;

  /// A selection was copied: a small message for a moment.
  void _copied() {
    if (!mounted) return;
    setState(() => _toast = true);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = false);
    });
  }

  void _openKeyboard() {
    if (mounted && _mode != Mode.keyboard && _mode != Mode.mobile) {
      setState(() => _mode = Mode.keyboard);
    }
  }

  /// The computer says where the focus is now.
  ///  - Option 1 (default): a field you can type into opens the keyboard by itself; anywhere
  ///    else leaves the touchpad alone.
  ///  - Option 2 ("Only when I click a field"): the focus moving by itself never opens it,
  ///    only a click with the pointer does (see [_clicked]).
  /// While windows or browser tabs are being switched the focus bounces around, so option 1
  /// waits for it to settle and the last place it landed decides.
  void _textFocus(bool typeable) {
    _focusTimer?.cancel();
    _focusTimer = null;
    final st = Settings.instance;
    if (!typeable || !mounted || !st.autoKeyboard) return;
    if (st.autoKeyboardOnClick) {
      // Only counts when you had just clicked (the click made the field take the focus).
      final sinceClick = DateTime.now().difference(
        Connection.instance.lastClickAt,
      );
      if (sinceClick < const Duration(milliseconds: 1500)) _openKeyboard();
      return;
    }
    if (SwitchGuard.active) {
      _focusTimer = Timer(const Duration(milliseconds: 700), _openKeyboard);
    } else {
      _openKeyboard();
    }
  }

  /// A click with the pointer. In option 2, if the focus is in a field you can type into (it
  /// was there already, or the click just put it there), open the keyboard. The short wait lets
  /// the computer report a focus the click moved elsewhere.
  void _clicked() {
    final st = Settings.instance;
    if (!st.autoKeyboard || !st.autoKeyboardOnClick || !mounted) return;
    _clickTimer?.cancel();
    _clickTimer = Timer(const Duration(milliseconds: 400), () {
      if (Connection.instance.focusTypeable == true) _openKeyboard();
    });
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _clickTimer?.cancel();
    Connection.instance.onClick = null;
    Connection.instance.onCopied = null;
    _toastTimer?.cancel();
    Connection.instance.onTextFocus = null;
    super.dispose();
  }

  /// Keeps the screen below alive when the layout around it changes (rotating, or
  /// turning the notch bar on or off). Without it the Mouse screen would be rebuilt,
  /// and its clean-up would flip the phone back to landscape.
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'content');

  /// The mode shown before this one: a single tap on the mode button goes back to it.
  Mode? _previous;

  void _setMode(Mode m) => setState(() {
    if (m != _mode) _previous = _mode;
    _mode = m;
  });

  double? _appliedBrightness;

  /// The phone's screen brightness for what is on screen (Settings > Screen brightness).
  void _applyBrightness(double level) {
    if (level == _appliedBrightness) return;
    _appliedBrightness = level;
    WindowMode.setBrightness(level);
  }

  @override
  Widget build(BuildContext context) {
    final c = Connection.instance;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _body(c)),
          _copiedToast(),
        ],
      ),
    );
  }

  Widget _copiedToast() => Positioned(
    left: 0,
    right: 0,
    bottom: 56,
    child: IgnorePointer(
      child: AnimatedOpacity(
        opacity: _toast ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Center(
          child: Container(
            key: const Key('copiedToast'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 16, color: Colors.greenAccent),
                SizedBox(width: 6),
                Text('Copied', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _body(Connection c) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, Settings.instance]),
      builder: (context, _) {
        final st = Settings.instance;
        final modes = availableModes(
          mouse: st.mouseTab,
          pad: st.padTab,
          voice: st.voiceTab,
          mobile: st.mobileTab,
          order: st.modeOrderList,
        );
        // A tab that was switched off in Settings falls back to the keyboard.
        if (!modes.contains(_mode)) _mode = Mode.keyboard;
        _applyBrightness(st.brightnessFor(_mode.name));
        final content = KeyedSubtree(
          key: _contentKey,
          child: Column(
            children: [
              if (c.active?.effective == null) _StatusBanner(c),
              Expanded(
                child: switch (_mode) {
                  Mode.keyboard => const KeyboardScreen(),
                  Mode.mouse => const MouseScreen(),
                  Mode.pad => const PadScreen(),
                  Mode.voice => const VoiceScreen(),
                  Mode.mobile => const MobileScreen(),
                },
              ),
            ],
          ),
        );
        if (st.useNotchBar(
          hasNotch: _cutoutRect(MediaQuery.of(context)) != null,
        )) {
          return _NotchLayout(
            mode: _mode,
            modes: modes,
            onMode: _setMode,
            previous: _previous,
            content: content,
          );
        }
        return SafeArea(
          child: Column(
            children: [
              _TopBar(
                mode: _mode,
                modes: modes,
                onMode: _setMode,
                previous: _previous,
              ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

/// The strip under the bar while no computer is reachable. Offline the whole app can still be
/// explored; tapping the strip opens the list of computers.
class _StatusBanner extends StatelessWidget {
  final Connection c;
  const _StatusBanner(this.c);

  @override
  Widget build(BuildContext context) {
    final active = c.active;
    final phase = active?.phase;
    final offline = phase == null || phase == Phase.idle;
    final String text;
    if (phase == Phase.connecting) {
      text = 'Connecting to ${active!.device.title}...';
    } else if (offline && active != null && active.waiting) {
      text = active.tokenRejected
          ? '${active.device.title}: the agent has a new pairing code - pair again (QR code or USB)'
          : 'Looking for ${active.device.title}... (tap to choose another)';
    } else if (offline) {
      text = Settings.instance.devices.isEmpty
          ? 'Offline - tap to add a computer'
          : 'Offline - tap to choose a computer';
    } else {
      text = 'Connection lost - reconnecting...';
    }
    return InkWell(
      onTap: offline
          ? () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const DevicesSheet(),
            )
          : null,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF5A2A2A),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ),
    );
  }
}

/// The cut-out (notch / camera hole) in window coordinates, if the phone has one.
Rect? _cutoutRect(MediaQueryData mq) {
  Rect? r;
  for (final f in mq.displayFeatures) {
    if (f.type == DisplayFeatureType.cutout) {
      r = r == null ? f.bounds : r.expandToInclude(f.bounds);
    }
  }
  return r;
}

/// "Use notch area" layout: no top bar. The options become icons in a bar along
/// the notch's edge (a vertical rail in landscape, a strip across the top in
/// portrait), split into two groups so none sits behind the camera hole. The
/// content gets the whole screen.
class _NotchLayout extends StatelessWidget {
  final Mode? previous;
  final Mode mode;
  final List<Mode> modes;
  final ValueChanged<Mode> onMode;
  final Widget content;
  const _NotchLayout({
    this.previous,
    required this.mode,
    required this.modes,
    required this.onMode,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final pad = mq.padding;
    final cutout = _cutoutRect(mq);
    final landscape = size.width > size.height;
    final onLeft = cutout == null || cutout.center.dx < size.width / 2;
    final items = [
      // The edit menu (copy, paste ...) sits in the top-left corner, first in the bar.
      if (Settings.instance.editMenu) const EditMenuButton(),
      const _DeviceButton(compact: true),
      const _TransportButton(compact: true),
      if (Settings.instance.remoteAudioEnabled)
        const RemoteAudioButton(compact: true),
      // With only the keyboard left there is nothing to switch between.
      if (modes.length > 1)
        ModeButton(
          mode: mode,
          modes: modes,
          onMode: onMode,
          previous: previous,
          side: landscape
              ? (onLeft ? MenuSide.right : MenuSide.left)
              : MenuSide.below,
        ),
      IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.tune, size: 20),
        onPressed: () =>
            openSettings(context, scope: SettingsScope.forMode(mode)),
      ),
    ];

    if (landscape) {
      // Landscape: the notch is on a side edge, so the bar is a vertical rail on that side.
      final depth = cutout == null
          ? 0.0
          : (onLeft ? cutout.right : size.width - cutout.left);
      final span = cutout == null ? null : (cutout.top, cutout.bottom);
      final plan = planNotchBar(
        n: items.length,
        length: size.height,
        cutout: span,
        extent: _NotchStrip.extent,
      );
      final second = plan.second > 0;
      final thickness = math.max(plan.extent + 4, depth + 4);
      final strip = SizedBox(
        width: thickness + (second ? _NotchStrip.secondExtent + 4 : 0),
        child: _NotchStrip(
          axis: Axis.vertical,
          cutout: span,
          items: items,
          plan: plan,
          firstThickness: thickness,
          // The second column is on the side of the content, away from the screen edge.
          secondFirst: second && !onLeft,
        ),
      );
      final body = Expanded(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            onLeft ? 0 : pad.left,
            pad.top,
            onLeft ? pad.right : 0,
            pad.bottom,
          ),
          child: content,
        ),
      );
      return Row(children: onLeft ? [strip, body] : [body, strip]);
    }

    // Portrait: the notch is at the top, so the bar runs along the top edge.
    final span = cutout == null ? null : (cutout.left, cutout.right);
    final plan = planNotchBar(
      n: items.length,
      length: size.width,
      cutout: span,
      extent: _NotchStrip.extent,
    );
    final thickness = math.max(plan.extent + 4, (cutout?.bottom ?? 0) + 4);
    final strip = SizedBox(
      height: thickness + (plan.second > 0 ? _NotchStrip.secondExtent + 4 : 0),
      child: _NotchStrip(
        axis: Axis.horizontal,
        cutout: span,
        items: items,
        plan: plan,
        firstThickness: thickness,
      ),
    );
    return Column(
      children: [
        strip,
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
            child: content,
          ),
        ),
      ],
    );
  }
}

/// Lays the icons out along one axis, in two groups with the cut-out between them. Around a wide
/// notch the cells shrink, and icons that still do not fit go on a second line.
class _NotchStrip extends StatelessWidget {
  static const extent = 48.0;
  static const secondExtent = 40.0;

  final Axis axis;

  /// Where the notch starts and ends along [axis], or null if there is none.
  final (double, double)? cutout;
  final List<Widget> items;
  final NotchPlan plan;

  /// How thick the first line is (it must clear the notch's depth).
  final double firstThickness;

  /// The second line comes before the first one (a rail on the right edge of the screen).
  final bool secondFirst;
  const _NotchStrip({
    required this.axis,
    required this.cutout,
    required this.items,
    required this.plan,
    required this.firstThickness,
    this.secondFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget w, double size) => SizedBox.square(
      dimension: size,
      child: Center(child: w),
    );
    final firstCount = items.length - plan.second;
    final first = Flex(
      direction: axis,
      children: [
        for (final w in items.take(plan.before)) cell(w, plan.extent),
        const Spacer(),
        for (final w in items.skip(plan.before).take(firstCount - plan.before))
          cell(w, plan.extent),
      ],
    );
    if (plan.second == 0) return first;
    // Past the notch's depth the whole length is free: the rest, spread evenly.
    final second = Flex(
      direction: axis,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [for (final w in items.skip(firstCount)) cell(w, secondExtent)],
    );
    final horizontal = axis == Axis.horizontal;
    Widget line(double thickness, Widget w) => horizontal
        ? SizedBox(height: thickness, child: w)
        : SizedBox(width: thickness, child: w);
    final lines = [line(firstThickness, first), line(secondExtent + 4, second)];
    final crossAxis = horizontal ? Axis.vertical : Axis.horizontal;
    return Flex(
      direction: crossAxis,
      children: secondFirst ? lines.reversed.toList() : lines,
    );
  }
}

class _TopBar extends StatelessWidget {
  final Mode? previous;
  final Mode mode;
  final List<Mode> modes;
  final ValueChanged<Mode> onMode;
  const _TopBar({
    this.previous,
    required this.mode,
    required this.modes,
    required this.onMode,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 600;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 4),
          if (Settings.instance.editMenu) const EditMenuButton(),
          _DeviceButton(compact: narrow),
          _TransportButton(compact: narrow),
          const Spacer(),
          if (Settings.instance.remoteAudioEnabled)
            RemoteAudioButton(compact: narrow),
          if (modes.length > 1)
            ModeButton(
              mode: mode,
              modes: modes,
              onMode: onMode,
              previous: previous,
              showLabel: !narrow,
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            onPressed: () =>
                openSettings(context, scope: SettingsScope.forMode(mode)),
          ),
        ],
      ),
    );
  }
}

class _DeviceButton extends StatelessWidget {
  final bool compact;
  const _DeviceButton({required this.compact});

  /// Listens by itself: in the side-bar layout this is a `const` widget, which the parent's
  /// rebuild would skip, leaving a stale icon.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Connection.instance,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final c = Connection.instance;
    final count = c.activeCount;
    final current = c.active;
    final color = current?.phase == Phase.active
        ? deviceColor(current!.device.id)
        : Colors.white54;
    void open() => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DevicesSheet(),
    );
    final icon = Badge(
      label: Text('$count'),
      isLabelVisible: count > 1,
      backgroundColor: color,
      textColor: Colors.black,
      child: Icon(Icons.computer, size: 20, color: color),
    );
    return Semantics(
      label: 'Computers',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: c.switchToPreviousConnected,
        onDoubleTap: c.switchToNextConnected,
        onLongPress: open,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 8,
            vertical: 12,
          ),
          child: compact
              ? icon
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        c.active?.device.title ?? 'Computers',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final bool compact;
  const _TransportButton({required this.compact});

  /// Listens by itself: in the side-bar layout this is a `const` widget, which the parent's
  /// rebuild would skip, leaving a stale icon.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Connection.instance,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final c = Connection.instance;
    final s = c.active;
    if (s == null) return const SizedBox.shrink();
    final eff = s.effective;
    final color = eff == null
        ? Colors.redAccent
        : s.usingFallback
        ? Colors.orangeAccent
        : Colors.greenAccent;
    // With several live computers, a transport glyph would change whenever the
    // user picked a different computer (USB on one, Wi-Fi on another). Keep this
    // control visually separate from the computer switch; the sheet names the
    // active computer and shows its real links. With one computer, the glyph
    // still follows USB/Wi-Fi/Bluetooth fail-over as before.
    final icon = c.activeCount > 1
        ? Icons.link
        : eff == null
        ? Icons.sync_problem
        : switch (eff.transport) {
            Transport.bluetooth => Icons.bluetooth,
            Transport.usb => Icons.usb,
            Transport.wifi => Icons.wifi,
          };
    void open() => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TransportSheet(),
    );
    if (compact) {
      return IconButton(
        tooltip: 'Connection: ${eff?.transport.label ?? 'Offline'}',
        icon: Icon(icon, size: 20, color: color),
        onPressed: open,
      );
    }
    return TextButton.icon(
      onPressed: open,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        eff?.transport.label ?? 'Offline',
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

/// Pick Wi-Fi or Bluetooth for the active computer. Both links stay connected,
/// so the switch is instant; if the chosen one drops, the other takes over.
class TransportSheet extends StatelessWidget {
  const TransportSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Connection.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.active;
        if (s == null) {
          return const SizedBox(
            height: 100,
            child: Center(child: Text('No computer connected')),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${s.device.title}: send input over',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<Transport>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: Transport.wifi,
                    icon: Icon(Icons.wifi),
                    label: Text('Wi-Fi'),
                  ),
                  ButtonSegment(
                    value: Transport.bluetooth,
                    icon: Icon(Icons.bluetooth),
                    label: Text('Bluetooth'),
                  ),
                ],
                selected: {
                  s.preferred == Transport.usb ? Transport.wifi : s.preferred,
                },
                onSelectionChanged: (v) => s.setPreferred(v.first),
              ),
              if (s.usingFallback)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${s.preferred.label} is down - using ${s.effective!.transport.label} '
                    'until it is back.',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              if (s.device.useUsb) _LinkRow(s, Transport.usb),
              _LinkRow(s, Transport.wifi),
              _LinkRow(s, Transport.bluetooth),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  s.device.useUsb
                      ? 'The USB cable is used automatically while it is plugged in. '
                            'The links stay connected, so switching is instant.'
                      : 'Both links stay connected, so switching is instant.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LinkRow extends StatelessWidget {
  final Session session;
  final Transport t;
  const _LinkRow(this.session, this.t);

  @override
  Widget build(BuildContext context) {
    final l = session.link(t);
    final status = switch (l.state) {
      LinkState.connected => 'Connected',
      LinkState.connecting => 'Connecting...',
      LinkState.disconnected =>
        l.error ??
            (t == Transport.bluetooth &&
                    !session.wants(t) &&
                    session.syncNote != null
                ? session.syncNote!
                : (session.wants(t) ? 'Not connected' : 'Off')),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(switch (t) {
        Transport.wifi => Icons.wifi,
        Transport.bluetooth => Icons.bluetooth,
        Transport.usb => Icons.usb,
      }),
      title: Text(t.label),
      subtitle: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: switch (l.state) {
        LinkState.connected => const Icon(
          Icons.check_circle,
          color: Colors.greenAccent,
        ),
        LinkState.connecting => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        LinkState.disconnected => TextButton(
          onPressed: () => session.startLink(t),
          child: Text(session.wants(t) ? 'Retry' : 'Connect'),
        ),
      },
    );
  }
}
