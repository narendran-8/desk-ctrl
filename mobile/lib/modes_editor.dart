import 'package:flutter/material.dart';

import 'modes.dart';
import 'settings.dart';

/// Settings: put the modes in your order (drag the handle) and switch tabs on or off.
/// The order is where the app starts, what a tap on the mode button cycles through,
/// and the order of the long-press menu.
class ModesEditor extends StatelessWidget {
  const ModesEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) => _content(),
    );
  }

  Widget _content() {
    final s = Settings.instance;
    final order = s.modeOrderList;
    bool enabled(Mode m) => switch (m) {
      Mode.keyboard => true,
      Mode.mouse => s.mouseTab,
      Mode.pad => s.padTab,
      Mode.voice => s.voiceTab,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          title: Text('Modes'),
          subtitle: Text(
            'Drag to set the order. Tap the mode button to go to the next one; '
            'long-press it to pick from the rest.',
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            final list = [...order];
            list.insert(to, list.removeAt(from));
            s.update(() => s.modeOrder = [for (final m in list) m.name]);
          },
          children: [
            for (var i = 0; i < order.length; i++)
              ListTile(
                key: ValueKey(order[i]),
                leading: Icon(order[i].icon),
                title: Text(order[i].label),
                subtitle: i == 0 ? const Text('Starts here') : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (order[i] != Mode.keyboard)
                      Switch(
                        value: enabled(order[i]),
                        onChanged: (v) => s.update(() {
                          if (order[i] == Mode.mouse) s.mouseTab = v;
                          if (order[i] == Mode.pad) s.padTab = v;
                          if (order[i] == Mode.voice) s.voiceTab = v;
                        }),
                      ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
