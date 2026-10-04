import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'console_style.dart';

/// Opens [child] in the console side panel. When [origin] (the tapped tile's
/// global rect) is given, the tile morphs into the panel and back on close.
///
/// Performance budget for older Galaxy Tab A hardware: the morph only tweens
/// one rect and crossfades two layers. No backdrop blur, no animated shadows,
/// and hard-edge clipping while moving.
Future<void> showConsolePanel(
  BuildContext context,
  Widget child, {
  Rect? origin,
}) => Navigator.of(
  context,
).push(ConsolePanelRoute<void>(origin: origin, child: child));

class ConsolePanelRoute<T> extends PopupRoute<T> {
  ConsolePanelRoute({required this.child, this.origin});
  final Widget child;
  final Rect? origin;

  @override
  Color? get barrierColor => const Color(0x8C000000);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Close panel';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 480);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(context, animation, secondaryAnimation) => Theme(
    data: ConsoleStyle.theme(context),
    child: Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: const TextStyle(
          color: ConsoleStyle.text,
          fontSize: 15,
          height: 1.35,
        ),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );

  @override
  Widget buildTransitions(context, animation, secondaryAnimation, child) =>
      _PanelMorph(animation: animation, origin: origin, child: child);
}

/// Slightly underdamped spring: settles with a barely visible overshoot.
class ConsoleSpringCurve extends Curve {
  const ConsoleSpringCurve();
  static final _simulation = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 170, ratio: .8),
    0,
    1,
    0,
  );
  // Seconds of spring time mapped onto the route's 0..1 progress.
  static const _span = .48;
  @override
  double transformInternal(double t) => _simulation.x(t * _span);
}

class _PanelMorph extends StatefulWidget {
  const _PanelMorph({
    required this.animation,
    required this.origin,
    required this.child,
  });
  final Animation<double> animation;
  final Rect? origin;
  final Widget child;

  @override
  State<_PanelMorph> createState() => _PanelMorphState();
}

class _PanelMorphState extends State<_PanelMorph> {
  late final CurvedAnimation _geometry = CurvedAnimation(
    parent: widget.animation,
    curve: const ConsoleSpringCurve(),
    reverseCurve: Curves.easeInCubic,
  );
  // Tile face fades out early; panel content fades in once there is room.
  late final CurvedAnimation _tileFade = CurvedAnimation(
    parent: widget.animation,
    curve: const Interval(0, .3, curve: Curves.easeOut),
  );
  late final CurvedAnimation _contentFade = CurvedAnimation(
    parent: widget.animation,
    curve: const Interval(.25, .75, curve: Curves.easeOut),
  );
  late final Animation<double> _tileOpacity = ReverseAnimation(_tileFade);

  @override
  void dispose() {
    _geometry.dispose();
    _tileFade.dispose();
    _contentFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _build(constraints.biggest),
  );

  Widget _build(Size size) {
    final padding = MediaQuery.paddingOf(context);
    final width = math.min(460.0, size.width - 24);
    final target = Rect.fromLTRB(
      size.width - padding.right - 12 - width,
      padding.top + 12,
      size.width - padding.right - 12,
      size.height - padding.bottom - 12,
    );
    // Without a source tile the panel glides in from just off its resting spot.
    final origin = widget.origin ?? target.translate(48, 0);
    final content = FadeTransition(
      opacity: _contentFade,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: target.width,
        maxWidth: target.width,
        minHeight: target.height,
        maxHeight: target.height,
        child: widget.child,
      ),
    );
    final tileFace = IgnorePointer(
      child: FadeTransition(
        opacity: _tileOpacity,
        child: const ColoredBox(color: ConsoleStyle.surface),
      ),
    );
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _geometry,
          builder: (context, _) {
            final t = _geometry.value;
            final settled =
                widget.animation.status == AnimationStatus.completed;
            final rect = Rect.lerp(origin, target, t)!;
            final radius = BorderRadius.circular(
              lerpDouble(ConsoleStyle.controlRadius, 24, t.clamp(0, 1))!,
            );
            return Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF132232), ConsoleStyle.panel],
                  ),
                  borderRadius: radius,
                  border: Border.all(color: ConsoleStyle.border),
                  // The soft shadow only appears at rest; blurring a moving
                  // shadow every frame is the expensive part.
                  boxShadow: settled
                      ? const [
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 40,
                            offset: Offset(-8, 0),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  clipBehavior: settled ? Clip.antiAlias : Clip.hardEdge,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [content, tileFace],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Fades and lifts a panel section in after the morph opens; [index] staggers
/// sections about 40 ms apart.
class ConsoleStagger extends StatefulWidget {
  const ConsoleStagger({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<ConsoleStagger> createState() => _ConsoleStaggerState();
}

class _ConsoleStaggerState extends State<ConsoleStagger> {
  CurvedAnimation? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == null || _animation != null) return;
    final start = math.min(.35 + widget.index * .04, .65);
    _animation = CurvedAnimation(
      parent: route,
      curve: Interval(
        start,
        math.min(start + .35, 1),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _animation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = _animation;
    if (animation == null) return widget.child;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .12),
          end: Offset.zero,
        ).animate(animation),
        child: widget.child,
      ),
    );
  }
}

/// A [Column] whose children enter one after another; spacers count as steps
/// too, which keeps the rhythm even.
class ConsoleStaggerColumn extends StatelessWidget {
  const ConsoleStaggerColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
  });
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    children: [
      for (var i = 0; i < children.length; i++)
        children[i] is SizedBox
            ? children[i]
            : ConsoleStagger(index: i, child: children[i]),
    ],
  );
}

/// Shared panel header: an icon badge, title, optional subtitle and close.
class ConsolePanelHeader extends StatelessWidget {
  const ConsolePanelHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.closeTooltip,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ConsoleIconBadge(icon: icon, size: 48),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: -.2,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: ConsoleStyle.muted),
              ),
          ],
        ),
      ),
      IconButton(
        tooltip: closeTooltip,
        onPressed: () => Navigator.pop(context),
        style: IconButton.styleFrom(
          backgroundColor: ConsoleStyle.surface,
          foregroundColor: ConsoleStyle.muted,
          fixedSize: const Size(44, 44),
        ),
        icon: const Icon(Icons.close_rounded, size: 22),
      ),
    ],
  );
}

class ConsoleIconBadge extends StatelessWidget {
  const ConsoleIconBadge({
    super.key,
    required this.icon,
    this.size = 36,
    this.active = true,
  });
  final IconData icon;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: active ? ConsoleStyle.accentDim : ConsoleStyle.pressed,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(
      icon,
      size: size * .5,
      color: active ? ConsoleStyle.accent : ConsoleStyle.faint,
    ),
  );
}

/// Small uppercase section caption used inside panels.
class ConsoleSectionLabel extends StatelessWidget {
  const ConsoleSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        height: 1,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: ConsoleStyle.faint,
      ),
    ),
  );
}

/// Inset tile used to group content inside a panel.
class ConsoleInset extends StatelessWidget {
  const ConsoleInset({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ConsoleStyle.background.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(ConsoleStyle.controlRadius),
      border: Border.all(color: ConsoleStyle.hairline),
    ),
    child: child,
  );
}
