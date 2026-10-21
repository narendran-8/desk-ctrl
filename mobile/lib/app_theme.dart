import 'package:flutter/material.dart';

import 'settings.dart';

/// The colours of the app's surfaces, for the chosen theme and accent colour.
@immutable
class DeskColors extends ThemeExtension<DeskColors> {
  final Color bg, key, keyAlt, keyMod, pad, padActive, padOff, body, accent;
  const DeskColors({
    required this.bg,
    required this.key,
    required this.keyAlt,
    required this.keyMod,
    required this.pad,
    required this.padActive,
    required this.padOff,
    required this.body,
    required this.accent,
  });

  /// A softer version of the accent, for "aiming" / selected backgrounds.
  Color get accentDim => Color.lerp(bg, accent, 0.45)!;

  @override
  DeskColors copyWith({Color? bg, Color? accent}) => DeskColors(
    bg: bg ?? this.bg,
    key: key,
    keyAlt: keyAlt,
    keyMod: keyMod,
    pad: pad,
    padActive: padActive,
    padOff: padOff,
    body: body,
    accent: accent ?? this.accent,
  );

  @override
  DeskColors lerp(DeskColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DeskColors(
      bg: l(bg, other.bg),
      key: l(key, other.key),
      keyAlt: l(keyAlt, other.keyAlt),
      keyMod: l(keyMod, other.keyMod),
      pad: l(pad, other.pad),
      padActive: l(padActive, other.padActive),
      padOff: l(padOff, other.padOff),
      body: l(body, other.body),
      accent: l(accent, other.accent),
    );
  }
}

extension DeskTheme on BuildContext {
  DeskColors get desk =>
      Theme.of(this).extension<DeskColors>() ??
      AppTheme.colors('soft', AppTheme.defaultAccent);
}

/// Themes: `soft` (the original dark grey), `amoled` (true black, for OLED screens: unlit
/// pixels use no power) and `tinted` ("Black lite": near-black with a tint of the accent colour).
class AppTheme {
  static const themes = ['soft', 'amoled', 'tinted'];
  static const defaultAccent = Color(0xFF4F8CFF);

  /// The accent colours to choose from.
  static const accents = <Color>[
    Color(0xFF4F8CFF), // blue
    Color(0xFF00D4BE), // teal
    Color(0xFF39FF88), // green
    Color(0xFFFFD166), // amber
    Color(0xFFFF8A4F), // orange
    Color(0xFFFF5C7A), // red / pink
    Color(0xFFB57CFF), // purple
    Color(0xFFE6E8EC), // white
  ];

  static String label(String theme) => switch (theme) {
    'amoled' => 'Full black',
    'tinted' => 'Black lite',
    _ => 'Soft dark',
  };

  static String hint(String theme) => switch (theme) {
    'amoled' => 'True black, saves battery on AMOLED screens',
    'tinted' => 'Near black with a tint of your colour',
    _ => 'The original dark grey',
  };

  static DeskColors colors(String theme, Color accent) {
    switch (theme) {
      case 'amoled':
        return DeskColors(
          bg: Colors.black,
          key: const Color(0xFF16181D),
          keyAlt: const Color(0xFF1F2229),
          keyMod: const Color(0xFF292D36),
          pad: const Color(0xFF0E0F12),
          padActive: const Color(0xFF16181D),
          padOff: const Color(0xFF060607),
          body: Colors.black,
          accent: accent,
        );
      case 'tinted':
        final h = HSLColor.fromColor(accent).hue;
        Color t(double s, double l) => HSLColor.fromAHSL(1, h, s, l).toColor();
        return DeskColors(
          bg: t(0.35, 0.05),
          key: t(0.28, 0.12),
          keyAlt: t(0.25, 0.17),
          keyMod: t(0.22, 0.22),
          pad: t(0.30, 0.10),
          padActive: t(0.32, 0.15),
          padOff: t(0.30, 0.065),
          body: t(0.32, 0.075),
          accent: accent,
        );
      default:
        return DeskColors(
          bg: const Color(0xFF14161B),
          key: const Color(0xFF2B2F38),
          keyAlt: const Color(0xFF3A3F4B),
          keyMod: const Color(0xFF454B5C),
          pad: const Color(0xFF2A2E37),
          padActive: const Color(0xFF323847),
          padOff: const Color(0xFF17191E),
          body: const Color(0xFF1B1E24),
          accent: accent,
        );
    }
  }

  static ThemeData of(Settings s) {
    final accent = Color(s.accent);
    final c = colors(s.theme, accent);
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme.dark(
        primary: accent,
        surface: c.bg,
        surfaceContainerHigh: s.theme == 'amoled'
            ? const Color(0xFF0E0F12)
            : null,
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.bg),
      dialogTheme: DialogThemeData(backgroundColor: c.key),
      extensions: [c],
    );
  }
}
