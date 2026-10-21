import 'dart:convert';

/// A key of the user's own for the round menu: a name, a key and the modifiers held with it
/// (Ctrl+Shift+T, Alt+Left, F11 ...).
class CustomKey {
  /// Saved in the menu layout: `custom_<n>`.
  final String id;
  final String label;

  /// Which modifiers are held: see [ctrl], [shift], [alt], [superKey].
  final int mods;

  /// USB HID usage (< 0x100), or `0x8000 | consumer usage` for media / system keys.
  final int key;

  /// Holding a finger on the option repeats it, like holding the key.
  final bool repeats;
  const CustomKey({
    required this.id,
    required this.label,
    required this.mods,
    required this.key,
    this.repeats = false,
  });

  static const ctrl = 1, shift = 2, alt = 4, superKey = 8;
  static const maxLabel = 12;
  static const maxKeys = 20;

  /// The modifier HID codes, in the order they are pressed.
  List<int> get modKeys => [
    if (mods & ctrl != 0) 0xE0,
    if (mods & shift != 0) 0xE1,
    if (mods & alt != 0) 0xE2,
    if (mods & superKey != 0) 0xE3,
  ];

  /// "Ctrl+Shift+T".
  String get chord => [
    if (mods & ctrl != 0) 'Ctrl',
    if (mods & shift != 0) 'Shift',
    if (mods & alt != 0) 'Alt',
    if (mods & superKey != 0) 'Super',
    keyName(key),
  ].join('+');

  /// The same for the small picture on the wedge: "C+S" over "T".
  String get modInitials => [
    if (mods & ctrl != 0) 'C',
    if (mods & shift != 0) 'S',
    if (mods & alt != 0) 'A',
    if (mods & superKey != 0) 'W',
  ].join('+');

  CustomKey copyWith({String? label, int? mods, int? key, bool? repeats}) =>
      CustomKey(
        id: id,
        label: label ?? this.label,
        mods: mods ?? this.mods,
        key: key ?? this.key,
        repeats: repeats ?? this.repeats,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'mods': mods,
    'key': key,
    'repeats': repeats,
  };

  /// Null for anything that is not a usable key.
  static CustomKey? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], label = j['label'], mods = j['mods'], key = j['key'];
    if (id is! String || !RegExp(r'^custom_\d+$').hasMatch(id)) return null;
    if (label is! String || label.trim().isEmpty) return null;
    if (mods is! int || mods < 0 || mods > 15) return null;
    if (key is! int || keyName(key) == null) return null;
    return CustomKey(
      id: id,
      label: label.trim().substring(0, label.trim().length.clamp(0, maxLabel)),
      mods: mods,
      key: key,
      repeats: j['repeats'] == true,
    );
  }

  static String encodeList(List<CustomKey> keys) =>
      jsonEncode([for (final k in keys) k.toJson()]);

  /// Reads the saved list; entries that are not usable, and ids seen twice, are dropped.
  static List<CustomKey> decodeList(String text) {
    try {
      final list = jsonDecode(text);
      if (list is! List) return [];
      final seen = <String>{};
      return [
        for (final j in list)
          if (fromJson(j) case final k? when seen.add(k.id)) k,
      ].take(maxKeys).toList();
    } catch (_) {
      return [];
    }
  }

  /// The next free id.
  static String nextId(List<CustomKey> keys) {
    var n = 1;
    for (final k in keys) {
      n = [n, int.parse(k.id.substring(7)) + 1].reduce((a, b) => a > b ? a : b);
    }
    return 'custom_$n';
  }
}

/// The keys that can be chosen, in the order of the picker: (name, HID code).
final List<(String, int)> pickableKeys = [
  for (var i = 0; i < 26; i++) (String.fromCharCode(0x41 + i), 0x04 + i),
  for (var i = 1; i <= 9; i++) ('$i', 0x1E + i - 1),
  ('0', 0x27),
  for (var i = 1; i <= 12; i++) ('F$i', 0x3A + i - 1),
  ('Enter', 0x28),
  ('Esc', 0x29),
  ('Backspace', 0x2A),
  ('Tab', 0x2B),
  ('Space', 0x2C),
  ('-', 0x2D),
  ('=', 0x2E),
  ('[', 0x2F),
  (']', 0x30),
  ('\\', 0x31),
  (';', 0x33),
  ("'", 0x34),
  ('`', 0x35),
  (',', 0x36),
  ('.', 0x37),
  ('/', 0x38),
  ('Print Screen', 0x46),
  ('Insert', 0x49),
  ('Home', 0x4A),
  ('Page Up', 0x4B),
  ('Delete', 0x4C),
  ('End', 0x4D),
  ('Page Down', 0x4E),
  ('Right', 0x4F),
  ('Left', 0x50),
  ('Down', 0x51),
  ('Up', 0x52),
  ('Volume up', 0x80E9),
  ('Volume down', 0x80EA),
  ('Mute', 0x80E2),
  ('Play / pause', 0x80CD),
  ('Next track', 0x80B5),
  ('Previous track', 0x80B6),
  ('Brightness up', 0x806F),
  ('Brightness down', 0x8070),
];

/// The picker's groups: letters, numbers, function keys, editing / arrows, punctuation, media.
final List<(String, List<(String, int)>)> pickableGroups = [
  (
    'Letters',
    [
      for (final k in pickableKeys)
        if (k.$2 >= 0x04 && k.$2 <= 0x1D) k,
    ],
  ),
  (
    'Numbers',
    [
      for (final k in pickableKeys)
        if (k.$2 >= 0x1E && k.$2 <= 0x27) k,
    ],
  ),
  (
    'Function keys',
    [
      for (final k in pickableKeys)
        if (k.$2 >= 0x3A && k.$2 <= 0x45) k,
    ],
  ),
  (
    'Editing and arrows',
    [
      for (final k in pickableKeys)
        if ({
          0x28,
          0x29,
          0x2A,
          0x2B,
          0x2C,
          0x46,
          0x49,
          0x4A,
          0x4B,
          0x4C,
          0x4D,
          0x4E,
          0x4F,
          0x50,
          0x51,
          0x52,
        }.contains(k.$2))
          k,
    ],
  ),
  (
    'Punctuation',
    [
      for (final k in pickableKeys)
        if (k.$2 >= 0x2D && k.$2 <= 0x38 && k.$2 != 0x32) k,
    ],
  ),
  (
    'Media and screen',
    [
      for (final k in pickableKeys)
        if (k.$2 >= 0x8000) k,
    ],
  ),
];

String? keyName(int hid) {
  for (final k in pickableKeys) {
    if (k.$2 == hid) return k.$1;
  }
  return null;
}

/// A name short enough for the picture on a wedge.
String shortKeyName(int hid) {
  const short = {
    'Backspace': 'Bksp',
    'Page Up': 'PgUp',
    'Page Down': 'PgDn',
    'Print Screen': 'PrtSc',
    'Volume up': 'Vol+',
    'Volume down': 'Vol-',
    'Play / pause': 'Play',
    'Next track': 'Next',
    'Previous track': 'Prev',
    'Brightness up': 'Br+',
    'Brightness down': 'Br-',
    'Insert': 'Ins',
    'Delete': 'Del',
  };
  final n = keyName(hid) ?? '?';
  return short[n] ?? n;
}
