import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'connection.dart';
import 'settings.dart';
import 'voice.dart';

/// The Voice screen, a mode like the keyboard and the trackpad: hold a button and speak.
///  - Dictate: what you say is typed on the computer.
///  - Command: what you say is an action ("copy", "scroll down", "open terminal", "close window").
/// The speech is recognised on the computer (see agent/src/voice.rs).
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with WidgetsBindingObserver {
  final v = VoiceController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    v.attach();
  }

  /// Leaving the app while listening stops the microphone.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) v.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    v.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([v, Settings.instance, Connection.instance]),
      builder: (context, _) {
        final wide = MediaQuery.of(context).size.width > 560;
        final transcript = Expanded(child: _Transcript(v));
        final buttons = _Buttons(v, row: !wide);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: wide
              ? Row(children: [transcript, const SizedBox(width: 16), buttons])
              : Column(
                  children: [transcript, const SizedBox(height: 12), buttons],
                ),
        );
      },
    );
  }
}

class _Transcript extends StatelessWidget {
  final VoiceController v;
  const _Transcript(this.v);

  IconData _icon(String kind) => switch (kind) {
    'typed' => Icons.keyboard,
    'ran' => Icons.bolt,
    'ask' => Icons.help_outline,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final d = context.desk;
    final status = v.error ?? (v.status.isEmpty ? _hint() : v.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              v.error != null ? Icons.error_outline : Icons.mic,
              size: 18,
              color: v.error != null ? Colors.redAccent : d.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status,
                key: const Key('voiceStatus'),
                style: TextStyle(
                  fontSize: 15,
                  color: v.error != null ? Colors.redAccent : Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (v.phase == VoicePhase.listening)
          ValueListenableBuilder<double>(
            valueListenable: v.level,
            builder: (_, level, _) => LinearProgressIndicator(
              value: level,
              minHeight: 6,
              color: d.accent,
              backgroundColor: Colors.white12,
            ),
          )
        else
          const SizedBox(height: 6),
        if (v.pending != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                FilledButton(
                  key: const Key('voiceRun'),
                  onPressed: v.confirm,
                  child: Text('Run "${v.pending!.label}"'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('voiceDismiss'),
                  onPressed: v.dismiss,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: v.history.isEmpty
              ? Center(
                  child: Text(
                    'Dictate: your words are typed on the computer.\n'
                    'Command: say copy, paste, undo, scroll down, volume up, open terminal, close window ...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, height: 1.5),
                  ),
                )
              : ListView(
                  children: [
                    for (final e in v.history)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          _icon(e.kind),
                          size: 18,
                          color: Colors.white54,
                        ),
                        title: Text(e.text),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _hint() => Settings.instance.voiceHold
      ? 'Hold a button and speak'
      : 'Tap a button, speak, tap again';
}

class _Buttons extends StatelessWidget {
  final VoiceController v;
  final bool row;
  const _Buttons(this.v, {required this.row});

  @override
  Widget build(BuildContext context) {
    final children = [
      _TalkButton(
        v,
        asCommand: false,
        icon: Icons.keyboard_voice,
        label: 'Dictate',
      ),
      const SizedBox(width: 16, height: 16),
      _TalkButton(v, asCommand: true, icon: Icons.bolt, label: 'Command'),
    ];
    return row
        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: children)
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          );
  }
}

class _TalkButton extends StatelessWidget {
  final VoiceController v;
  final bool asCommand;
  final IconData icon;
  final String label;
  const _TalkButton(
    this.v, {
    required this.asCommand,
    required this.icon,
    required this.label,
  });

  bool get _mine => v.busy && v.command == asCommand;

  void _down() {
    final hold = Settings.instance.voiceHold;
    if (hold) {
      v.begin(asCommand: asCommand);
    } else if (_mine && v.phase == VoicePhase.listening) {
      v.end();
    } else {
      v.begin(asCommand: asCommand);
    }
  }

  void _up() {
    if (Settings.instance.voiceHold) v.end();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.desk;
    final active = _mine && v.phase != VoicePhase.idle;
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: Container(
        key: Key(asCommand ? 'voiceCommand' : 'voiceDictate'),
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? d.accent : d.key,
          border: Border.all(color: d.accent, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: active ? Colors.white : d.accent),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: active ? Colors.white : Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
