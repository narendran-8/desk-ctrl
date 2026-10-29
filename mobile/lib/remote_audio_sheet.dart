import 'package:flutter/material.dart';

import 'remote_audio.dart';
import 'settings.dart';

void openRemoteAudio(BuildContext context) {
  final audio = RemoteAudio.instance;
  if (!audio.active && audio.phase != RemoteAudioPhase.connecting) {
    audio.discover();
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => const RemoteAudioSheet(),
  );
}

class RemoteAudioButton extends StatelessWidget {
  const RemoteAudioButton({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: RemoteAudio.instance,
    builder: (context, _) {
      final audio = RemoteAudio.instance;
      final enabled = Settings.instance.remoteAudioEnabled;
      final color = audio.active
          ? Theme.of(context).colorScheme.primary
          : audio.phase == RemoteAudioPhase.error
          ? Theme.of(context).colorScheme.error
          : null;
      return IconButton(
        key: const Key('remoteAudioButton'),
        tooltip: enabled
            ? 'Audio output'
            : 'Remote audio is disabled in Settings',
        color: color,
        icon: Icon(
          audio.active ? Icons.speaker_group : Icons.speaker_outlined,
          size: compact ? 19 : 20,
        ),
        onPressed: enabled ? () => openRemoteAudio(context) : null,
      );
    },
  );
}

class RemoteAudioSheet extends StatelessWidget {
  const RemoteAudioSheet({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: RemoteAudio.instance,
    builder: (context, _) {
      final a = RemoteAudio.instance;
      final source = a.sourceLabel;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.speaker_group_outlined),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Audio Output',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh outputs',
                            onPressed: a.active ? null : a.discover,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          a.phoneSource ? Icons.phone_android : Icons.computer,
                        ),
                        title: const Text('Source'),
                        subtitle: Text(source),
                        trailing: _StateChip(a.phase),
                      ),
                      SegmentedButton<String>(
                        key: const Key('remoteAudioSource'),
                        segments: const [
                          ButtonSegment(
                            value: 'computer',
                            label: Text('Computer'),
                            icon: Icon(Icons.computer),
                          ),
                          ButtonSegment(
                            value: 'phone',
                            label: Text('This phone'),
                            icon: Icon(Icons.phone_android),
                          ),
                        ],
                        selected: {Settings.instance.remoteAudioSource},
                        onSelectionChanged:
                            a.active ||
                                a.phase == RemoteAudioPhase.connecting ||
                                a.phase == RemoteAudioPhase.discovering
                            ? null
                            : (values) => a.chooseSource(values.first),
                      ),
                      if (a.phoneSource)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Android 10+: approve sharing (Entire screen for all apps). Only media audio is captured, with no microphone or screen images. Apps can block capture. Phone playback remains audible; volume controls the computer stream.',
                          ),
                        ),
                      if (a.message != null)
                        Container(
                          key: const Key('remoteAudioMessage'),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                (a.phase == RemoteAudioPhase.error
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary)
                                    .withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(a.message!),
                        ),
                      const Text(
                        'Play through',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        child: a.phase == RemoteAudioPhase.discovering
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  for (final d in a.destinations)
                                    ListTile(
                                      key: Key('audioDestination-${d.key}'),
                                      enabled:
                                          !a.active &&
                                          a.phase !=
                                              RemoteAudioPhase.connecting,
                                      onTap:
                                          a.active ||
                                              a.phase ==
                                                  RemoteAudioPhase.connecting
                                          ? null
                                          : () => a.select(d.key),
                                      leading: Icon(
                                        d.phone
                                            ? Icons.phone_android
                                            : Icons.speaker,
                                      ),
                                      title: Text(d.label),
                                      subtitle: d.phone
                                          ? const Text(
                                              'Current Android media output',
                                            )
                                          : null,
                                      trailing: Icon(
                                        a.selected == d.key
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                      ),
                                    ),
                                  if (a.destinations.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Text(
                                        'No destinations are available. Connect the source by Wi-Fi or USB.',
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      if (a.active) ...[
                        Row(
                          children: [
                            IconButton(
                              key: const Key('remoteAudioMute'),
                              tooltip: a.muted ? 'Unmute' : 'Mute',
                              onPressed: () => a.setGain(mute: !a.muted),
                              icon: Icon(
                                a.muted ? Icons.volume_off : Icons.volume_up,
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                key: const Key('remoteAudioVolume'),
                                value: a.volume,
                                label: '${(a.volume * 100).round()}%',
                                onChanged: (v) => a.setGain(level: v),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text('${(a.volume * 100).round()}%'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SwitchListTile(
                key: const Key('remoteAudioAutoReconnect'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Reconnect automatically'),
                dense: true,
                visualDensity: VisualDensity.compact,
                value: Settings.instance.remoteAudioAutoReconnect,
                onChanged: (value) {
                  Settings.instance.update(
                    () => Settings.instance.remoteAudioAutoReconnect = value,
                  );
                  a.preferencesChanged();
                },
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('remoteAudioStartStop'),
                onPressed: a.phase == RemoteAudioPhase.discovering
                    ? null
                    : a.active || a.phase == RemoteAudioPhase.connecting
                    ? a.stop
                    : a.start,
                icon: Icon(
                  a.active || a.phase == RemoteAudioPhase.connecting
                      ? Icons.stop
                      : Icons.play_arrow,
                ),
                label: Text(
                  a.active || a.phase == RemoteAudioPhase.connecting
                      ? 'Stop'
                      : 'Start',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _StateChip extends StatelessWidget {
  const _StateChip(this.phase);
  final RemoteAudioPhase phase;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      RemoteAudioPhase.active => ('Active', Colors.green),
      RemoteAudioPhase.connecting => ('Connecting', Colors.orange),
      RemoteAudioPhase.discovering => ('Finding', Colors.blue),
      RemoteAudioPhase.error => ('Error', Theme.of(context).colorScheme.error),
      RemoteAudioPhase.idle => ('Stopped', Colors.grey),
    };
    return Chip(
      label: Text(label),
      side: BorderSide.none,
      backgroundColor: color.withValues(alpha: .18),
      visualDensity: VisualDensity.compact,
    );
  }
}
