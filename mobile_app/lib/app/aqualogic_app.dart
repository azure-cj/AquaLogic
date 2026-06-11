import 'package:aqualogic/app/startup/splash_screen.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class AquaLogicApp extends StatelessWidget {
  const AquaLogicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaLogic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.teal,
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}
