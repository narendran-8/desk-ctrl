import 'package:flutter/material.dart';

import 'custom_key.dart';
import 'edit_menu.dart';
import 'settings.dart';

/// Settings: choose which options the round (edit) menu has, in which row and order.
/// Row 1 is the ring nearest the button. Tap an option to move or remove it.
class EditMenuEditor extends StatelessWidget {
  const EditMenuEditor({super.key});

  static void _save(List<List<String>> rows) {
    final s = Settings.instance;
    s.update(() => s.editLayout = encodeEditLayout(rows));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) {
        final rows = decodeEditLayout(Settings.instance.editLayout);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              title: Text('Menu options'),
              subtitle: Text(
                'Row 1 is next to the button. Tap an option to move or remove it, '
                'or add new ones.',
              ),
            ),
            for (var r = 0; r < rows.length; r++) _row(context, rows, r),
            Wrap(
              children: [
                if (rows.length < maxEditRows)
                  TextButton.icon(
                    key: const Key('editAddRow'),
                    onPressed: () => _save([
                      ...rows,
                      ['copy'],
                    ]),
                    icon: const Icon(Icons.add),
                    label: const Text('Add row'),
                  ),
                TextButton.icon(
                  key: const Key('editReset'),
                  onPressed: () => _save(const []),
                  icon: const Icon(Icons.restore),
                  label: const Text('Standard options'),
                ),
              ],
            ),
            _customSection(context),
          ],
        );
      },
    );
  }

  static const _newCustom = '__new_custom__';

  static void _saveCustom(List<CustomKey> keys) {
    final s = Settings.instance;
    s.update(() => s.editCustom = CustomKey.encodeList(keys));
  }

  /// "Custom keys": the user's own shortcuts, to edit or delete; new ones are made here or
  /// from "Add" in a row.
  Widget _customSection(BuildContext context) {
    final keys = customKeys();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          title: Text('Custom keys'),
          subtitle: Text(
            'Your own shortcut: a key with Ctrl, Shift, Alt or Super (Ctrl+Shift+T, F11, Alt+Left ...). '
            'Add it to a row with "Add".',
          ),
        ),
        for (final k in keys)
          ListTile(
            key: Key('custom.${k.id}'),
            dense: true,
            leading: customAction(k)
                .icon(Theme.of(context).colorScheme.onSurface),
            title: Text(k.label),
            subtitle: Text(
              k.repeats ? '${k.chord} (repeats when held)' : k.chord,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('customEdit.${k.id}'),
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () async {
                    final made = await _editCustom(context, existing: k);
                    if (made != null) {
                      _saveCustom([
                        for (final x in keys) x.id == k.id ? made : x,
                      ]);
                    }
                  },
                ),
                IconButton(
                  key: Key('customDelete.${k.id}'),
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () {
                    _saveCustom([
                      for (final x in keys)
                        if (x.id != k.id) x,
                    ]);
                    // A deleted key also leaves the rows.
                    _save(decodeEditLayout(Settings.instance.editLayout));
                  },
                ),
              ],
            ),
          ),
        if (keys.length < CustomKey.maxKeys)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton.icon(
              key: const Key('customNew'),
              onPressed: () async {
                final made = await _editCustom(context);
                if (made != null) _saveCustom([...keys, made]);
              },
              icon: const Icon(Icons.add),
              label: const Text('Create a custom key'),
            ),
          ),
      ],
    );
  }

  /// The dialog for a custom key: name, modifiers, key, repeat. Null when cancelled.
  static Future<CustomKey?> _editCustom(
    BuildContext context, {
    CustomKey? existing,
  }) {
    final keys = customKeys();
    return showDialog<CustomKey>(
      context: context,
      builder: (_) => _CustomKeyDialog(
        existing ??
            CustomKey(id: CustomKey.nextId(keys), label: '', mods: 0, key: 0),
        isNew: existing == null,
      ),
    );
  }

  Widget _row(BuildContext context, List<List<String>> rows, int r) {
    final row = rows[r];
    List<List<String>> copy() => [
      for (final x in rows) [...x],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Row ${r + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: Key('editRowUp$r'),
                tooltip: 'Move row closer to the button',
                icon: const Icon(Icons.arrow_upward, size: 20),
                onPressed: r == 0
                    ? null
                    : () {
                        final c = copy();
                        c.insert(r - 1, c.removeAt(r));
                        _save(c);
                      },
              ),
              IconButton(
                key: Key('editRowDown$r'),
                tooltip: 'Move row away from the button',
                icon: const Icon(Icons.arrow_downward, size: 20),
                onPressed: r == rows.length - 1
                    ? null
                    : () {
                        final c = copy();
                        c.insert(r + 1, c.removeAt(r));
                        _save(c);
                      },
              ),
              IconButton(
                key: Key('editRowDelete$r'),
                tooltip: 'Remove row',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: rows.length == 1
                    ? null
                    : () => _save(copy()..removeAt(r)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < row.length; i++)
                PopupMenuButton<String>(
                  key: Key('editOption$r.$i'),
                  tooltip: '',
                  onSelected: (v) {
                    final c = copy();
                    final item = c[r].removeAt(i);
                    if (v == 'earlier') c[r].insert(i - 1, item);
                    if (v == 'later') c[r].insert(i + 1, item);
                    _save(c);
                  },
                  itemBuilder: (_) => [
                    if (i > 0)
                      const PopupMenuItem(
                        value: 'earlier',
                        child: Text('Move earlier'),
                      ),
                    if (i < row.length - 1)
                      const PopupMenuItem(
                        value: 'later',
                        child: Text('Move later'),
                      ),
                    if (rows.length > 1 || row.length > 1)
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove'),
                      ),
                  ],
                  child: Chip(
                    avatar: editActionFor(row[i])!
                        .icon(Theme.of(context).colorScheme.onSurface),
                    label: Text(editActionFor(row[i])!.label),
                  ),
                ),
              if (row.length < maxEditPerRow)
                ActionChip(
                  key: Key('editAdd$r'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  onPressed: () async {
                    final id = await showDialog<String>(
                      context: context,
                      builder: (_) => SimpleDialog(
                        title: const Text('Add an option'),
                        children: [
                          for (final a in [
                            ...editCatalog.values,
                            for (final k in customKeys()) customAction(k),
                          ])
                            SimpleDialogOption(
                              key: Key('editPick.${a.id}'),
                              onPressed: () => Navigator.pop(context, a.id),
                              child: Row(
                                children: [
                                  a.icon(Colors.white),
                                  const SizedBox(width: 16),
                                  Text(a.label),
                                ],
                              ),
                            ),
                          SimpleDialogOption(
                            key: const Key('editPickNewCustom'),
                            onPressed: () => Navigator.pop(context, _newCustom),
                            child: const Row(
                              children: [
                                Icon(Icons.add_circle_outline),
                                SizedBox(width: 16),
                                Text('Create a custom key...'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                    if (id == _newCustom) {
                      if (!context.mounted) return;
                      final made = await _editCustom(context);
                      if (made != null) {
                        _saveCustom([...customKeys(), made]);
                        _save(copy()..[r].add(made.id));
                      }
                      return;
                    }
                    if (id != null) _save(copy()..[r].add(id));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomKeyDialog extends StatefulWidget {
  final CustomKey start;
  final bool isNew;
  const _CustomKeyDialog(this.start, {required this.isNew});

  @override
  State<_CustomKeyDialog> createState() => _CustomKeyDialogState();
}

class _CustomKeyDialogState extends State<_CustomKeyDialog> {
  late final _name = TextEditingController(text: widget.start.label);
  late int _mods = widget.start.mods;
  late int? _key = widget.start.key == 0 ? null : widget.start.key;
  late bool _repeats = widget.start.repeats;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _key != null;

  CustomKey get _made => CustomKey(
    id: widget.start.id,
    label: _name.text.trim(),
    mods: _mods,
    key: _key!,
    repeats: _repeats,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'New custom key' : 'Edit custom key'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('customName'),
              controller: _name,
              maxLength: CustomKey.maxLabel,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (label, bit) in const [
                  ('Ctrl', CustomKey.ctrl),
                  ('Shift', CustomKey.shift),
                  ('Alt', CustomKey.alt),
                  ('Super', CustomKey.superKey),
                ])
                  FilterChip(
                    key: Key('customMod.$label'),
                    label: Text(label),
                    selected: _mods & bit != 0,
                    onSelected: (v) =>
                        setState(() => _mods = v ? _mods | bit : _mods & ~bit),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (title, group) in pickableGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 0,
                children: [
                  for (final k in group)
                    ChoiceChip(
                      key: Key('customKey.${k.$1}'),
                      label: Text(k.$1),
                      visualDensity: VisualDensity.compact,
                      selected: _key == k.$2,
                      onSelected: (_) => setState(() => _key = k.$2),
                    ),
                ],
              ),
            ],
            SwitchListTile(
              key: const Key('customRepeat'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat while held'),
              value: _repeats,
              onChanged: (v) => setState(() => _repeats = v),
            ),
            if (_valid)
              Text(
                'Sends ${_made.chord}',
                style: const TextStyle(color: Colors.white60),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('customSave'),
          onPressed: _valid ? () => Navigator.pop(context, _made) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
