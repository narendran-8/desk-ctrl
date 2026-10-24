import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'keyboard_screen.dart';
import 'pad_screen.dart';
import 'settings.dart';

/// A compact laptop layout that can rotate between wide and upright keyboards.
class MobileScreen extends StatefulWidget {
  const MobileScreen({super.key});

  @override
  State<MobileScreen> createState() => _MobileScreenState();
}

class _MobileScreenState extends State<MobileScreen> {
  bool _phoneMedia = false;
  bool _keyboardFirst = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _rotate() {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    SystemChrome.setPreferredOrientations([
      portrait ? DeviceOrientation.landscapeLeft : DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Widget _touchpad(bool compact) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.desk.body,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Settings.instance,
                builder: (context, _) => TouchPad(
                  enabled: Settings.instance.padEnabled,
                  compact: compact,
                  phoneMedia:
                      _phoneMedia && Settings.instance.padPhoneMediaButton,
                ),
              ),
            ),
            Positioned(
              top: compact ? 32 : 0,
              left: compact ? 0 : 4,
              child: Flex(
                direction: compact ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Rotate Mobile screen',
                    constraints: BoxConstraints.tightFor(
                      width: compact ? 36 : 28,
                      height: compact ? 36 : 28,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: compact ? 20 : 14,
                    icon: const Icon(
                      Icons.screen_rotation,
                      color: Colors.white70,
                    ),
                    onPressed: _rotate,
                  ),
                  if (Settings.instance.padPhoneMediaButton) ...[
                    SizedBox(height: compact ? 4 : 0, width: compact ? 0 : 4),
                    IconButton(
                      tooltip: _phoneMedia
                          ? 'Mobile media on'
                          : 'Mobile media off',
                      constraints: BoxConstraints.tightFor(
                        width: compact ? 36 : 28,
                        height: compact ? 36 : 28,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: compact ? 20 : 14,
                      icon: Icon(
                        Icons.smartphone,
                        color: _phoneMedia
                            ? context.desk.accent
                            : Colors.white70,
                      ),
                      onPressed: () =>
                          setState(() => _phoneMedia = !_phoneMedia),
                    ),
                  ],
                  SizedBox(height: compact ? 4 : 0, width: compact ? 0 : 4),
                  IconButton(
                    tooltip: _keyboardFirst
                        ? 'Move trackpad to top'
                        : 'Move keyboard to top',
                    constraints: BoxConstraints.tightFor(
                      width: compact ? 36 : 28,
                      height: compact ? 36 : 28,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: compact ? 20 : 14,
                    icon: const Icon(Icons.swap_vert, color: Colors.white70),
                    onPressed: () =>
                        setState(() => _keyboardFirst = !_keyboardFirst),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final portrait = box.maxHeight > box.maxWidth;
      final Widget touchpad = portrait
          ? Expanded(child: _touchpad(true))
          : Expanded(flex: 2, child: _touchpad(false));
      final Widget keyboard = portrait
          ? SizedBox(
              height: math.min(360, box.maxHeight * 0.52),
              child: const KeyboardScreen(compact: true),
            )
          : const Expanded(flex: 3, child: KeyboardScreen());
      return Column(
        children: _keyboardFirst ? [keyboard, touchpad] : [touchpad, keyboard],
      );
    },
  );
}
