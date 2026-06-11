import 'dart:async';

import 'package:aqualogic/app/navigation/aqualogic_shell.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1600),
    this.next = const AquaLogicShell(),
  });

  final Duration duration;
  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _messages = [
    'Waking the tank...',
    'Checking tiny bubbles...',
    'Asking the sensors nicely...',
    'Polishing the water readings...',
    'Dashboard ready',
  ];

  late final AnimationController _swimController;
  late final AnimationController _bubbleController;
  Timer? _readyTimer;
  Timer? _messageTimer;
  var _messageIndex = 0;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _swimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _messageTimer = Timer.periodic(const Duration(milliseconds: 360), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1).clamp(0, _messages.length - 1);
      });
    });
    _readyTimer = Timer(widget.duration, _showApp);
  }

  void _showApp() {
    if (!mounted || _ready) return;
    _messageTimer?.cancel();
    _swimController.stop();
    _bubbleController.stop();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _messageTimer?.cancel();
    _swimController.dispose();
    _bubbleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _ready
          ? KeyedSubtree(key: const ValueKey('app-shell'), child: widget.next)
          : _SplashScene(
              key: const ValueKey('splash-scene'),
              swimAnimation: _swimController,
              bubbleAnimation: _bubbleController,
              statusText: _messages[_messageIndex],
            ),
    );
  }
}

class _SplashScene extends StatelessWidget {
  const _SplashScene({
    super.key,
    required this.swimAnimation,
    required this.bubbleAnimation,
    required this.statusText,
  });

  final Animation<double> swimAnimation;
  final Animation<double> bubbleAnimation;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.headerTop, AppColors.headerBottom],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: bubbleAnimation,
                  builder: (context, child) {
                    final width = MediaQuery.sizeOf(context).width;

                    return Stack(
                      children: List.generate(9, (index) {
                        final progress =
                            (bubbleAnimation.value + index * 0.13) % 1;
                        final size = 7.0 + (index % 3) * 5;
                        final leftFactor = 0.12 + (index * 0.11) % 0.78;

                        return Positioned(
                          left: width * leftFactor,
                          bottom: 42 + progress * 260,
                          child: Opacity(
                            opacity: (1 - progress).clamp(0.08, 0.42),
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  width: 1.4,
                                ),
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Image.asset(
                            'assets/images/aqualogic_icon.png',
                            fit: BoxFit.contain,
                            semanticLabel: 'AquaLogic app icon',
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'AquaLogic',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          statusText,
                          key: ValueKey(statusText),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 34),
                      SizedBox(
                        height: 44,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return AnimatedBuilder(
                              animation: swimAnimation,
                              builder: (context, child) {
                                final fishX =
                                    -44 +
                                    (constraints.maxWidth + 88) *
                                        swimAnimation.value;

                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fill(
                                      top: 27,
                                      child: Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.24,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: fishX,
                                      top: 0,
                                      child: child!,
                                    ),
                                  ],
                                );
                              },
                              child: const Icon(
                                LucideIcons.fish,
                                color: AppColors.mint,
                                size: 36,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 24,
                right: 24,
                bottom: 32,
                child: _SplashProgress(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashProgress extends StatelessWidget {
  const _SplashProgress();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        minHeight: 5,
        backgroundColor: Colors.white24,
        valueColor: AlwaysStoppedAnimation<Color>(
          AppColors.mint.withValues(alpha: 0.92),
        ),
      ),
    );
  }
}
