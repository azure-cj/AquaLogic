import 'package:flutter/material.dart';

/// Console design tokens. The console is a fixed dark surface that echoes the
/// AquaLogic enclosure: matte near-black steel with a single cyan LED line.
abstract final class ConsoleStyle {
  static const background = Color(0xFF070D14);
  static const panel = Color(0xFF0C1520);
  static const surface = Color(0xFF111D2A);
  static const pressed = Color(0xFF172636);
  static const border = Color(0x14FFFFFF);
  static const hairline = Color(0x10FFFFFF);
  static const accent = Color(0xFF22C3E6);
  static const accentDim = Color(0x2422C3E6);
  static const text = Color(0xFFE8F1F7);
  static const muted = Color(0xFF8FA3B5);
  static const faint = Color(0xFF5B6E80);
  static const good = Color(0xFF3DD6A0);
  static const warning = Color(0xFFF2B544);
  static const critical = Color(0xFFFF5D5D);

  static const panelRadius = 20.0;
  static const controlRadius = 14.0;

  /// Soft depth instead of outlines: a faint top highlight and one shadow.
  static BoxDecoration panelDecoration({Color color = panel}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(panelRadius),
    border: const Border(top: BorderSide(color: border)),
    boxShadow: const [
      BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
  );

  static const tabular = [FontFeature.tabularFigures()];

  static ThemeData theme(BuildContext context) => Theme.of(context).copyWith(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    splashFactory: NoSplash.splashFactory,
    iconTheme: const IconThemeData(color: text),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: muted),
    ),
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: background,
      surface: surface,
      onSurface: text,
      outline: border,
    ),
    textTheme: Theme.of(
      context,
    ).textTheme.apply(bodyColor: text, displayColor: text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: background,
        minimumSize: const Size(120, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
