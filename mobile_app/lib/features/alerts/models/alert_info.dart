import 'package:aqualogic/shared/models/reading_state.dart';
import 'package:flutter/material.dart';

class AlertInfo {
  const AlertInfo({
    required this.icon,
    required this.title,
    required this.message,
    required this.recommendation,
    required this.time,
    required this.state,
  });

  final IconData icon;
  final String title;
  final String message;
  final String recommendation;
  final String time;
  final ReadingState state;
}
