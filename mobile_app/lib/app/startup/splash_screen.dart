import 'dart:async';

import 'package:aqualogic/app/auth/auth_gate.dart';
import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/startup/widgets/startup_background.dart';
import 'package:aqualogic/app/startup/widgets/startup_bubbles.dart';
import 'package:aqualogic/app/startup/widgets/startup_waterline.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.minimumDisplayDuration = const Duration(milliseconds: 600),
    this.next = const AuthGate(animateInitialState: false),
  });

  final Duration minimumDisplayDuration;
  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _handoffDuration = Duration(milliseconds: 280);

  late final AnimationController _waterlineController;
  late final AnimationController _shortBubbleController;
  late final AnimationController _mediumBubbleController;
  late final AnimationController _settleController;
  Timer? _minimumDisplayTimer;

  var _minimumDisplayElapsed = false;
  var _startupResolved = false;
  var _reducedMotion = false;
  var _motionPreferenceRead = false;
  var _handoffScheduled = false;
  var _handoffStarted = false;
  var _showDestination = false;

  @override
  void initState() {
    super.initState();
    _waterlineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4100),
    );
    _shortBubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _mediumBubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _settleController = AnimationController(
      vsync: this,
      duration: _handoffDuration,
    )..addStatusListener(_onSettleStatusChanged);

    _minimumDisplayTimer = Timer(widget.minimumDisplayDuration, () {
      if (!mounted) return;
      _minimumDisplayElapsed = true;
      _scheduleHandoffIfReady();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _startupResolved = AuthScope.of(context).status != AuthStatus.checking;

    if (!_motionPreferenceRead || reducedMotion != _reducedMotion) {
      _motionPreferenceRead = true;
      _reducedMotion = reducedMotion;
      if (reducedMotion) {
        _stopAmbientAnimations();
        if (_handoffStarted) _settleController.value = 1;
      } else if (!_handoffStarted) {
        _startAmbientAnimations();
      }
    }

    _scheduleHandoffIfReady();
  }

  void _startAmbientAnimations() {
    _waterlineController.repeat();
    _shortBubbleController.repeat();
    _mediumBubbleController.repeat();
  }

  void _stopAmbientAnimations() {
    _waterlineController.stop();
    _shortBubbleController.stop();
    _mediumBubbleController.stop();
  }

  void _scheduleHandoffIfReady() {
    if (!_minimumDisplayElapsed ||
        !_startupResolved ||
        _handoffScheduled ||
        _handoffStarted) {
      return;
    }

    _handoffScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handoffScheduled = false;
      if (!mounted ||
          !_minimumDisplayElapsed ||
          !_startupResolved ||
          _handoffStarted) {
        return;
      }
      _beginHandoff();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _beginHandoff() {
    _handoffStarted = true;
    _minimumDisplayTimer?.cancel();
    if (_reducedMotion) {
      _settleController.value = 1;
      _stopAmbientAnimations();
    } else {
      _settleController.forward();
    }
    setState(() => _showDestination = true);
  }

  void _onSettleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _stopAmbientAnimations();
  }

  @override
  void dispose() {
    _minimumDisplayTimer?.cancel();
    _settleController.removeStatusListener(_onSettleStatusChanged);
    _waterlineController.dispose();
    _shortBubbleController.dispose();
    _mediumBubbleController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: AppColors.background,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: AnimatedSwitcher(
          duration: _reducedMotion
              ? const Duration(milliseconds: 140)
              : _handoffDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: <Widget>[...previousChildren, ?currentChild],
          ),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _showDestination
              ? KeyedSubtree(
                  key: const ValueKey('startup-destination'),
                  child: widget.next,
                )
              : _StartupScene(
                  key: const ValueKey('startup-scene'),
                  reducedMotion: _reducedMotion,
                  waterlineAnimation: _waterlineController,
                  shortBubbleAnimation: _shortBubbleController,
                  mediumBubbleAnimation: _mediumBubbleController,
                  settleAnimation: _settleController,
                ),
        ),
      ),
    );
  }
}

class _StartupScene extends StatelessWidget {
  const _StartupScene({
    super.key,
    required this.reducedMotion,
    required this.waterlineAnimation,
    required this.shortBubbleAnimation,
    required this.mediumBubbleAnimation,
    required this.settleAnimation,
  });

  final bool reducedMotion;
  final Animation<double> waterlineAnimation;
  final Animation<double> shortBubbleAnimation;
  final Animation<double> mediumBubbleAnimation;
  final Animation<double> settleAnimation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('startup-splash-screen'),
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          StartupBackground(reducedMotion: reducedMotion),
          Positioned.fill(
            child: StartupBubbles(
              key: const ValueKey('startup-bubbles'),
              waterlineClock: waterlineAnimation,
              shortClock: shortBubbleAnimation,
              mediumClock: mediumBubbleAnimation,
              settle: settleAnimation,
              reducedMotion: reducedMotion,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 620;
                return Center(
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      -constraints.maxHeight * (compact ? 0.035 : 0.075),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StartupBrand(reducedMotion: reducedMotion),
                          SizedBox(height: compact ? 22 : 28),
                          StartupWaterline(
                            key: const ValueKey('startup-waterline'),
                            clock: waterlineAnimation,
                            settle: settleAnimation,
                            reducedMotion: reducedMotion,
                          ),
                          SizedBox(height: compact ? 16 : 20),
                          const Text(
                            'Preparing AquaLogic',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupBrand extends StatelessWidget {
  const _StartupBrand({required this.reducedMotion});

  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reducedMotion
          ? const Duration(milliseconds: 160)
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(
          scale: reducedMotion ? 1 : 0.97 + (0.03 * value),
          child: child,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            image: true,
            label: 'AquaLogic logo',
            child: Image.asset(
              'assets/images/aqualogic_icon.png',
              key: const ValueKey('startup-brand-mark'),
              width: 76,
              height: 76,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'AquaLogic',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.45,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
