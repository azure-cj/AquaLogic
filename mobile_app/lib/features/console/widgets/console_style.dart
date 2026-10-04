import 'package:flutter/material.dart';

abstract final class ConsoleStyle {
  static const background = Color(0xFF071B28);
  static const surface = Color(0xFF102C3D);
  static const border = Color(0xFF28516A);
  static const accent = Color(0xFF20CEF0);
  static const text = Color(0xFFF4FAFF);
  static const muted = Color(0xFFB0C6D4);
  static const good = Color(0xFF74E0B3);
  static const warning = Color(0xFFFFC46B);
  static const critical = Color(0xFFFF91A3);
  static ThemeData theme(BuildContext context) => Theme.of(context).copyWith(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    iconTheme: const IconThemeData(color: text),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: text),
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
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
