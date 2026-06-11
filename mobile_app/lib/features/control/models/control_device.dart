import 'package:flutter/material.dart';

class ControlDevice {
  const ControlDevice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.schedule,
    required this.active,
    required this.autoMode,
    this.lastAction = 'Ready',
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String schedule;
  final bool active;
  final bool autoMode;
  final String lastAction;

  ControlDevice copyWith({
    String? title,
    String? subtitle,
    IconData? icon,
    String? schedule,
    bool? active,
    bool? autoMode,
    String? lastAction,
  }) {
    return ControlDevice(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      schedule: schedule ?? this.schedule,
      active: active ?? this.active,
      autoMode: autoMode ?? this.autoMode,
      lastAction: lastAction ?? this.lastAction,
    );
  }
}
