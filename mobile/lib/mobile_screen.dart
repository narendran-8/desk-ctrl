import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'keyboard_screen.dart';
import 'pad_screen.dart';
import 'settings.dart';

/// A compact laptop layout: touchpad above the full keyboard.
class MobileScreen extends StatelessWidget {
  const MobileScreen({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        flex: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.desk.body,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ListenableBuilder(
                listenable: Settings.instance,
                builder: (context, _) =>
                    TouchPad(enabled: Settings.instance.padEnabled),
              ),
            ),
          ),
        ),
      ),
      const Expanded(flex: 3, child: KeyboardScreen()),
    ],
  );
}
