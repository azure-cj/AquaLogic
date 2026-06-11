import 'package:aqualogic/shared/models/reading_state.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFEAF8FA);
  static const headerTop = Color(0xFF003F61);
  static const headerBottom = Color(0xFF00908F);
  static const teal = Color(0xFF17C6C8);
  static const tealDark = Color(0xFF006D87);
  static const mint = Color(0xFFD9FFF2);
  static const text = Color(0xFF06213A);
  static const muted = Color(0xFF638195);
  static const line = Color(0xFFCFE3E9);
  static const warning = Color(0xFFEBA51D);
  static const critical = Color(0xFFFF607A);
  static const success = Color(0xFF22C99A);
}

Color stateColor(ReadingState state) {
  return switch (state) {
    ReadingState.normal => AppColors.success,
    ReadingState.warning => AppColors.warning,
    ReadingState.critical => AppColors.critical,
  };
}
