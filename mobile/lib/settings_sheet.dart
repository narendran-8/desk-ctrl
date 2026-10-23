import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'edit_menu_editor.dart';
import 'key_sound.dart';
import 'modes.dart';
import 'modes_editor.dart';
import 'settings.dart';
import 'window_mode.dart';

/// Opens the settings as a sheet.
/// Which settings to show: those of the screen you are on, or everything.
enum SettingsScope {
  all,
  keyboard,
  pad,
  mouse,
  voice;

  static SettingsScope forMode(Mode m) => switch (m) {
    Mode.keyboard => keyboard,
    Mode.pad => pad,
    Mode.mouse => mouse,
    Mode.voice => voice,
  };

  String get title => switch (this) {
    all => 'Settings',
    keyboard => 'Keyboard settings',
    pad => 'Touchpad settings',
    mouse => 'Mouse settings',
    voice => 'Voice settings',
  };
}

void openSettings(
  BuildContext context, {
  SettingsScope scope = SettingsScope.all,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 680),
  builder: (sheet) => SettingsSheet(
    scope: scope,
    // "All settings" closes this sheet and opens the full one.
    onAll: () {
      Navigator.of(sheet).pop();
      openSettings(context);
    },
  ),
);

/// Settings, grouped into sections that open and close.
class SettingsSheet extends StatelessWidget {
  final SettingsScope scope;
  final VoidCallback? onAll;
  const SettingsSheet({super.key, this.scope = SettingsScope.all, this.onAll});

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    scope.title,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                if (scope != SettingsScope.all && onAll != null)
                  TextButton(
                    onPressed: onAll,
                    child: const Text('All settings'),
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                if (scope == SettingsScope.all ||
                    scope == SettingsScope.keyboard)
                  _Section(
                    icon: Icons.keyboard_outlined,
                    title: 'Keyboard',
                    summary: 'Keys, function row, click sound',
                    initiallyExpanded: true,
                    children: [
                      _switch(
                        'Function keys (F1-F12)',
                        'Off hides the F-row, so the other keys get bigger',
                        s.fnRow,
                        (v) => s.fnRow = v,
                      ),
                      _switch(
                        'Fn key',
                        'Brightness, volume and media keys on the F-row',
                        s.fnKey && s.fnRow,
                        (v) => s.fnKey = v,
                        enabled: s.fnRow,
                      ),
                      _switch(
                        'Backspace and Del on one key',
                        'Swipe the key left or right to switch between them',
                        s.joinDelete,
                        (v) => s.joinDelete = v,
                      ),
                      _switch(
                        'Auto-open keyboard',
                        'Switch to the keyboard when you click a text field on the computer',
                        s.autoKeyboard,
                        (v) => s.autoKeyboard = v,
                      ),
                      _switch(
                        'Only when I click a field',
                        'Open the keyboard only after you click with the touchpad pointer, not when a window or tab moves the focus by itself',
                        s.autoKeyboardOnClick,
                        (v) => s.autoKeyboardOnClick = v,
                        enabled: s.autoKeyboard,
                      ),
                      _switch(
                        'Edit menu button',
                        'A button in the top-left corner that fans out Copy, Cut, Paste, Undo and Select all',
                        s.editMenu,
                        (v) => s.editMenu = v,
                      ),
                      _switch(
                        'Keep the edit menu open',
                        'After choosing an option the menu stays, so you can tap Backspace or Enter again and again (hold them to repeat). It folds away by itself after a few idle seconds.',
                        s.editMenuStayOpen,
                        (v) => s.editMenuStayOpen = v,
                        enabled: s.editMenu,
                      ),
                      _switch(
                        'Key click sound',
                        null,
                        s.sound,
                        (v) => s.sound = v,
                      ),
                      ListTile(
                        title: const Text('Sound pack'),
                        trailing: DropdownButton<String>(
                          // "silent" is the same as turning the click sound off.
                          value: s.sound ? s.pack : 'silent',
                          items: [
                            for (final p in [...Settings.packs, 'silent'])
                              DropdownMenuItem(value: p, child: Text(p)),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            if (v == 'silent') {
                              s.update(() => s.sound = false);
                              return;
                            }
                            s.update(() {
                              s.sound = true;
                              s.pack = v;
                            });
                            await KeySound.instance.reloadIfNeeded();
                            KeySound.instance.play(KeyKind.key);
                          },
                        ),
                      ),
                      _slider(
                        'Click volume',
                        s.volume,
                        0,
                        1,
                        (v) => s.volume = v,
                        enabled: s.sound,
                      ),
                    ],
                  ),
                if (scope == SettingsScope.all || scope == SettingsScope.pad)
                  _Section(
                    icon: Icons.touch_app_outlined,
                    title: 'Touchpad',
                    summary: 'Speed, taps, buttons, gestures',
                    initiallyExpanded: scope == SettingsScope.pad,
                    children: [
                      _slider(
                        'Pointer speed',
                        s.pointerSpeed,
                        0.5,
                        4,
                        (v) => s.pointerSpeed = v,
                      ),
                      _switch(
                        'Touchpad on',
                        'Off: the pad ignores touches (the screen shows "Touchpad off")',
                        s.padEnabled,
                        (v) => s.padEnabled = v,
                      ),
                      _switch(
                        'Auto-open keyboard',
                        'Switch to the keyboard when a text field gets focus on the computer',
                        s.autoKeyboard,
                        (v) => s.autoKeyboard = v,
                      ),
                      _switch(
                        'Only when I click a field',
                        'Open the keyboard only after you click with the touchpad pointer, not when a window or tab moves the focus by itself',
                        s.autoKeyboardOnClick,
                        (v) => s.autoKeyboardOnClick = v,
                        enabled: s.autoKeyboard,
                      ),
                      _switch(
                        'Move the cursor with the phone',
                        'Hold a finger on the pad and tilt the phone, like on the Mouse screen: lean it right and the cursor goes right, tilt the top away and it goes up. The further you tilt, the faster it moves. Lift your finger to stop.',
                        s.padMotion,
                        (v) => s.padMotion = v,
                      ),
                      _slider(
                        'Motion speed',
                        s.padMotionSpeed,
                        200,
                        2500,
                        (v) => s.padMotionSpeed = v,
                        enabled: s.padMotion,
                      ),
                      _switch(
                        'Also without touching the screen',
                        'The cursor follows the tilt of the phone all the time (a tilt you keep up fades after a few seconds), and you can move it with a finger at the same moment. Off: only while a finger rests on the pad.',
                        s.padMotionAlways,
                        (v) => s.padMotionAlways = v,
                        enabled: s.padMotion,
                      ),
                      _switch(
                        'Invert motion',
                        null,
                        s.padMotionInvert,
                        (v) => s.padMotionInvert = v,
                        enabled: s.padMotion,
                      ),
                      _switch(
                        'Tap to click',
                        null,
                        s.tapToClick,
                        (v) => s.tapToClick = v,
                      ),
                      _switch(
                        'Copy on select',
                        'Selecting text with the pointer (drag, double or triple click) copies it and shows "Copied". Sends Ctrl+Insert, which never interrupts a program in a terminal.',
                        s.copyOnSelect,
                        (v) => s.copyOnSelect = v,
                      ),
                      _switch(
                        'Natural scrolling',
                        null,
                        s.naturalScroll,
                        (v) => s.naturalScroll = v,
                      ),
                      _switch(
                        'Two-finger swipe: Back / Forward',
                        'Swipe two fingers from right to left = Back, from left to right = Forward (Alt+Left / Alt+Right in the browser and file manager). Sideways two-finger scrolling is off while this is on.',
                        s.padSwipeNav,
                        (v) => s.padSwipeNav = v,
                      ),
                      _switch(
                        'Left / Right buttons',
                        'Show them under the touchpad. Off: the pad fills the area.',
                        s.padButtons,
                        (v) => s.padButtons = v,
                      ),
                      _switch(
                        'Screenshot gesture',
                        'Swipe down with three fingers to take a screenshot on the computer',
                        s.screenshotSwipe,
                        (v) => s.screenshotSwipe = v,
                      ),
                    ],
                  ),
                if (scope == SettingsScope.all || scope == SettingsScope.pad)
                  _Section(
                    icon: Icons.tune,
                    title: 'Touchpad edges',
                    summary: 'Volume, brightness, forward / back, play',
                    children: [
                      _switch(
                        'Phone media button',
                        'Show the Mobile switch at the top-left of the touchpad. When on, edge controls adjust media and brightness on this phone.',
                        s.padPhoneMediaButton,
                        (v) => s.padPhoneMediaButton = v,
                      ),
                      _switch(
                        'Edge controls',
                        'Left edge: volume. Right edge: brightness. Top edge: forward / back, '
                            'and a tap on the middle plays or pauses.',
                        s.padZones,
                        (v) => s.padZones = v,
                      ),
                      _switch(
                        'Window switcher (bottom edge)',
                        'Slide right: Alt+Tab. Slide left: Alt+Shift+Tab. Hold and move to see all windows.',
                        s.padWindows,
                        (v) => s.padWindows = v,
                        enabled: s.padZones,
                      ),
                      _switch(
                        'Browser tab switching',
                        'Tap the middle icon of the bottom strip to switch between windows and browser tabs (Ctrl+Tab)',
                        s.padTabSwitch,
                        (v) => s.padTabSwitch = v,
                        enabled: s.padZones && s.padWindows,
                      ),
                      ListTile(
                        enabled: s.padZones,
                        title: const Text('Top edge slide'),
                        trailing: DropdownButton<String>(
                          value: s.padTopMode,
                          items: const [
                            DropdownMenuItem(
                              value: 'seek',
                              child: Text('Forward / back'),
                            ),
                            DropdownMenuItem(
                              value: 'track',
                              child: Text('Next / previous track'),
                            ),
                          ],
                          onChanged: s.padZones
                              ? (v) {
                                  if (v != null)
                                    s.update(() => s.padTopMode = v);
                                }
                              : null,
                        ),
                      ),
                      ListTile(
                        enabled: s.padZones,
                        title: const Text('Forward / back speed'),
                        subtitle: Row(
                          children: [
                            const Text('Slow'),
                            Expanded(
                              child: Slider(
                                value: s.seekSpeed.toDouble(),
                                min: 1,
                                max: 5,
                                divisions: 4,
                                label: const [
                                  'Very slow',
                                  'Slow',
                                  'Normal',
                                  'Fast',
                                  'Very fast',
                                ][s.seekSpeed - 1],
                                onChanged: s.padZones
                                    ? (v) => s.update(
                                        () => s.seekSpeed = v.round(),
                                      )
                                    : null,
                              ),
                            ),
                            const Text('Fast'),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (scope == SettingsScope.all || scope == SettingsScope.mouse)
                  _Section(
                    icon: Icons.screen_rotation_alt_outlined,
                    title: 'Tilt mouse',
                    summary: 'Move the cursor by tilting the phone',
                    initiallyExpanded: scope == SettingsScope.mouse,
                    children: [
                      _slider(
                        'Tilt speed',
                        s.gyroSpeed,
                        200,
                        2500,
                        (v) => s.gyroSpeed = v,
                      ),
                      _switch(
                        'Invert direction',
                        null,
                        s.invertGyro,
                        (v) => s.invertGyro = v,
                      ),
                    ],
                  ),
                if (scope == SettingsScope.all || scope == SettingsScope.voice)
                  _Section(
                    icon: Icons.mic,
                    title: 'Voice',
                    summary: 'Dictate text, speak commands',
                    initiallyExpanded: scope == SettingsScope.voice,
                    children: [
                      _switch(
                        'Hold to talk',
                        'Hold the button while you speak. Off: tap once to start and once to stop.',
                        s.voiceHold,
                        (v) => s.voiceHold = v,
                      ),
                      _switch(
                        'Space after dictated text',
                        'So the next sentence does not stick to the last one',
                        s.voiceSpace,
                        (v) => s.voiceSpace = v,
                      ),
                      _switch(
                        'Press Enter after dictating',
                        'Sends what you said, for a chat box or a search field',
                        s.voiceEnter,
                        (v) => s.voiceEnter = v,
                      ),
                      _switch(
                        'Guess commands I did not word exactly',
                        'The small model (Needle) on the computer suggests an action; you are asked before it runs. Off by default; it needs more memory and CPU than speech recognition.',
                        s.voiceAi,
                        (v) => s.voiceAi = v,
                      ),
                      _switch(
                        'Ask before closing a window',
                        'Closing by voice always asks "Run it?" first',
                        s.voiceConfirmRisky,
                        (v) => s.voiceConfirmRisky = v,
                      ),
                      const ListTile(
                        title: Text('Voice engine'),
                        subtitle: Text(
                          'Speech is recognised on the computer (Whistle and Needle, offline). '
                          'Install it there once with setup_voice.sh, then restart the agent.',
                        ),
                      ),
                    ],
                  ),
                if (scope == SettingsScope.all)
                  _Section(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    summary: '${AppTheme.label(s.theme)} · colour',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final t in AppTheme.themes)
                              ChoiceChip(
                                label: Text(AppTheme.label(t)),
                                selected: s.theme == t,
                                selectedColor: context.desk.accentDim,
                                showCheckmark: false,
                                onSelected: (_) => s.update(() => s.theme = t),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(
                          AppTheme.hint(s.theme),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const ListTile(dense: true, title: Text('Colour')),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            for (final c in AppTheme.accents)
                              _Swatch(
                                color: c,
                                selected: s.accent == c.toARGB32(),
                                onTap: () =>
                                    s.update(() => s.accent = c.toARGB32()),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                _Section(
                  icon: Icons.brightness_6_outlined,
                  title: 'Screen brightness',
                  summary: 'Phone brightness for each screen',
                  children: [
                    if (scope == SettingsScope.all ||
                        scope == SettingsScope.keyboard)
                      _brightness(
                        'Keyboard',
                        s.brightKeyboard,
                        (v) => s.brightKeyboard = v,
                      ),
                    if (scope == SettingsScope.all ||
                        scope == SettingsScope.pad)
                      _brightness(
                        'Touchpad',
                        s.brightPad,
                        (v) => s.brightPad = v,
                      ),
                    if (scope == SettingsScope.all ||
                        scope == SettingsScope.mouse)
                      _brightness(
                        'Mouse',
                        s.brightMouse,
                        (v) => s.brightMouse = v,
                      ),
                  ],
                ),
                if (scope == SettingsScope.all)
                  const _Section(
                    icon: Icons.view_carousel_outlined,
                    title: 'Screens',
                    summary: 'Order and which screens are available',
                    children: [ModesEditor()],
                  ),
                if (scope == SettingsScope.all)
                  _Section(
                    icon: Icons.phone_android,
                    title: 'General',
                    summary: 'Display, feedback, connecting',
                    children: [
                      _switch(
                        'Edit menu button',
                        'A button in the top-left corner that fans out Copy, Cut, Paste, Undo and Select all',
                        s.editMenu,
                        (v) => s.editMenu = v,
                      ),
                      _switch(
                        'Keep the edit menu open',
                        'After choosing an option the menu stays, so you can tap Backspace or Enter again and again (hold them to repeat). It folds away by itself after a few idle seconds.',
                        s.editMenuStayOpen,
                        (v) => s.editMenuStayOpen = v,
                        enabled: s.editMenu,
                      ),
                      _switch(
                        'Hold to repeat',
                        'Holding Backspace, Delete, Enter ... in the menu repeats it',
                        s.editMenuHoldRepeat,
                        (v) => s.editMenuHoldRepeat = v,
                        enabled: s.editMenu,
                      ),
                      _slider(
                        'Fold away after ${s.editMenuIdleSeconds} s idle',
                        s.editMenuIdleSeconds.toDouble(),
                        2,
                        30,
                        (x) => s.editMenuIdleSeconds = x.round(),
                        enabled: s.editMenu,
                      ),
                      const EditMenuEditor(),
                      _switch(
                        'Copy on select',
                        'Selecting text with the pointer (drag, double or triple click) copies it and shows "Copied". Sends Ctrl+Insert, which never interrupts a program in a terminal.',
                        s.copyOnSelect,
                        (v) => s.copyOnSelect = v,
                      ),
                      _switch(
                        'Set up Wi-Fi and Bluetooth over USB',
                        'When connected by USB cable, also set up Wi-Fi and Bluetooth for that computer, so they take over when you unplug',
                        s.usbSync,
                        (v) => s.usbSync = v,
                      ),
                      ListTile(
                        title: const Text('Around the camera notch'),
                        subtitle: const Text(
                          'Auto: when the phone has a notch the top bar becomes icons beside it, '
                          'for a bigger keyboard. On: always. Off: a normal top bar.',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: SegmentedButton<String>(
                          key: const Key('notchBar'),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 'auto', label: Text('Auto')),
                            ButtonSegment(value: 'on', label: Text('On')),
                            ButtonSegment(value: 'off', label: Text('Off')),
                          ],
                          selected: {s.notchBar},
                          onSelectionChanged: (v) {
                            s.update(() => s.notchBar = v.first);
                            WindowMode.useCutout(v.first != 'off');
                          },
                        ),
                      ),
                      _switch(
                        'Haptic feedback',
                        null,
                        s.haptic,
                        (v) => s.haptic = v,
                      ),
                      _switch(
                        'Reconnect on start',
                        'Reconnect to the computers you were using last',
                        s.autoReconnect,
                        (v) => s.autoReconnect = v,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _switch(
    String title,
    String? subtitle,
    bool value,
    void Function(bool) set, {
    bool enabled = true,
  }) => SwitchListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: enabled ? (v) => Settings.instance.update(() => set(v)) : null,
  );

  /// 0 = Auto (the phone's own brightness), then 10% ... 100%.
  static Widget _brightness(
    String label,
    double v,
    void Function(double) set,
  ) => ListTile(
    title: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          v <= 0 ? 'Auto' : '${(v * 100).round()}%',
          style: const TextStyle(color: Colors.white60),
        ),
      ],
    ),
    subtitle: Slider(
      value: v.clamp(0, 1),
      min: 0,
      max: 1,
      divisions: 10,
      label: v <= 0 ? 'Auto' : '${(v * 100).round()}%',
      onChanged: (x) => Settings.instance.update(() => set(x)),
    ),
  );

  static Widget _slider(
    String label,
    double v,
    double min,
    double max,
    void Function(double) set, {
    bool enabled = true,
  }) => ListTile(
    enabled: enabled,
    title: Text(label),
    subtitle: Slider(
      value: v.clamp(min, max),
      min: min,
      max: max,
      onChanged: enabled ? (x) => Settings.instance.update(() => set(x)) : null,
    ),
  );
}

/// One group of settings: a card with an icon and a short summary that opens on tap.
class _Section extends StatelessWidget {
  final IconData icon;
  final String title, summary;
  final bool initiallyExpanded;
  final List<Widget> children;
  const _Section({
    required this.icon,
    required this.title,
    required this.summary,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(title),
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: scheme.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            summary,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          // A scrollable inside (the list of screens) must not share the page storage of the
          // tile itself: it would read the tile's saved "expanded" flag as its scroll offset,
          // which broke the whole screen.
          children: [
            PageStorage(
              bucket: PageStorageBucket(),
              child: Column(children: children),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round colour choice; the chosen one has a ring and a tick.
class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Colors.white : Colors.white24,
          width: selected ? 3 : 1,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 18, color: Colors.black87)
          : null,
    ),
  );
}
