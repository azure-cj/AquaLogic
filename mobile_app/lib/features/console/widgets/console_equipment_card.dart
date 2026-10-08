import 'package:flutter/material.dart';
import 'console_style.dart';

class ConsoleEquipmentCard extends StatefulWidget {
  const ConsoleEquipmentCard({
    super.key,
    required this.label,
    required this.status,
    required this.icon,
    required this.onTap,
    this.onHold,
    this.onMore,
    this.caption,
    this.readOnly = false,
    this.active = false,
    this.pending = false,
    this.alert = false,
  });
  final String label;
  final String status;
  final IconData icon;
  final VoidCallback? onTap;

  /// When set, pressing for [holdDuration] fires this; releasing early does
  /// nothing. Progress fills along the bottom edge.
  final VoidCallback? onHold;

  /// Opens the detail panel from a corner button, separate from the main tap.
  final VoidCallback? onMore;

  /// One short line under the status: the gesture hint or a flagged outcome.
  final String? caption;
  final bool readOnly;

  /// Device is confirmed on/running; tints the tile with the accent.
  final bool active;

  /// A command is waiting for device confirmation.
  final bool pending;

  /// The last command failed or its outcome is unknown.
  final bool alert;

  static const holdDuration = Duration(seconds: 1);

  @override
  State<ConsoleEquipmentCard> createState() => _ConsoleEquipmentCardState();
}

class _ConsoleEquipmentCardState extends State<ConsoleEquipmentCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _hold =
      AnimationController(
        vsync: this,
        duration: ConsoleEquipmentCard.holdDuration,
      )..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        _hold.value = 0;
        _press(false);
        widget.onHold?.call();
      });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _holdStart() {
    if (widget.onHold == null) return;
    _press(true);
    _hold.forward(from: 0);
  }

  void _holdEnd() {
    if (_hold.isAnimating) _hold.reverse();
    _press(false);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onHold != null;
    final active = widget.active && enabled;
    final iconColor = active
        ? ConsoleStyle.accent
        : enabled
        ? ConsoleStyle.text
        : ConsoleStyle.faint;
    final statusColor = widget.alert || widget.pending
        ? ConsoleStyle.warning
        : active
        ? ConsoleStyle.accent
        : enabled && !widget.readOnly
        ? ConsoleStyle.text
        : ConsoleStyle.muted;
    return Semantics(
      button: enabled,
      label:
          '${widget.label}, ${widget.status}'
          '${widget.caption == null ? '' : ', ${widget.caption}'}'
          '${widget.readOnly ? ', read only' : ''}',
      excludeSemantics: true,
      child: Listener(
        onPointerDown: widget.onHold == null ? null : (_) => _holdStart(),
        onPointerUp: widget.onHold == null ? null : (_) => _holdEnd(),
        onPointerCancel: widget.onHold == null ? null : (_) => _holdEnd(),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: widget.onTap != null && widget.onHold == null
              ? (_) => _press(true)
              : null,
          onTapUp: widget.onHold == null ? (_) => _press(false) : null,
          onTapCancel: widget.onHold == null ? () => _press(false) : null,
          child: AnimatedScale(
            scale: _pressed ? .97 : 1,
            duration: const Duration(milliseconds: 90),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _pressed
                    ? ConsoleStyle.pressed
                    : widget.alert
                    ? Color.alphaBlend(
                        ConsoleStyle.warning.withValues(alpha: .10),
                        ConsoleStyle.surface,
                      )
                    : active
                    ? ConsoleStyle.accentDim
                    : ConsoleStyle.surface,
                borderRadius: BorderRadius.circular(ConsoleStyle.controlRadius),
                border: Border(
                  top: BorderSide(
                    color: widget.alert
                        ? ConsoleStyle.warning.withValues(alpha: .4)
                        : active
                        ? ConsoleStyle.accent.withValues(alpha: .35)
                        : ConsoleStyle.border,
                  ),
                ),
              ),
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        _face(constraints, iconColor, statusColor, active),
                  ),
                  if (widget.onHold != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedBuilder(
                        animation: _hold,
                        builder: (context, _) => Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _hold.value,
                            child: Container(
                              height: 5,
                              color: ConsoleStyle.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _face(
    BoxConstraints constraints,
    Color iconColor,
    Color statusColor,
    bool active,
  ) {
    // Short phone-landscape tiles: one header line and the status.
    if (constraints.maxHeight < 100) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: ConsoleStyle.muted,
                    ),
                  ),
                ),
                if (widget.onMore != null)
                  Tooltip(
                    message: '${widget.label} details',
                    child: InkResponse(
                      onTap: widget.onMore,
                      radius: 18,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: ConsoleStyle.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              widget.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                height: 1,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ],
        ),
      );
    }
    final compact = constraints.maxHeight < 120;
    final trailing = widget.onMore != null
        ? IconButton(
            tooltip: '${widget.label} details',
            onPressed: widget.onMore,
            iconSize: 20,
            style: IconButton.styleFrom(
              foregroundColor: ConsoleStyle.muted,
              minimumSize: const Size(40, 40),
              fixedSize: const Size(40, 40),
            ),
            icon: const Icon(Icons.more_horiz_rounded),
          )
        : widget.readOnly
        ? const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(
              Icons.lock_outline,
              size: 16,
              color: ConsoleStyle.faint,
            ),
          )
        : widget.onTap != null
        ? const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
              Icons.chevron_right,
              size: 20,
              color: ConsoleStyle.faint,
            ),
          )
        : const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 10 : 14, 6, compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: compact ? 30 : 38,
                height: compact ? 30 : 38,
                decoration: BoxDecoration(
                  color: active
                      ? ConsoleStyle.accent.withValues(alpha: .22)
                      : ConsoleStyle.pressed,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.icon,
                  size: compact ? 17 : 21,
                  color: iconColor,
                ),
              ),
              const Spacer(),
              trailing,
            ],
          ),
          const Spacer(),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1,
              fontWeight: FontWeight.w600,
              color: ConsoleStyle.muted,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              widget.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 19 : 23,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
                color: statusColor,
              ),
            ),
          ),
          if (widget.caption != null && !compact) ...[
            const SizedBox(height: 4),
            Text(
              widget.caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: widget.alert ? FontWeight.w600 : FontWeight.w400,
                color: widget.alert ? ConsoleStyle.warning : ConsoleStyle.faint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
