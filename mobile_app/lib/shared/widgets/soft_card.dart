import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.standardSurface),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}
