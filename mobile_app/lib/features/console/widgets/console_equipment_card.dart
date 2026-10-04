import 'package:flutter/material.dart';
import 'console_style.dart';

class ConsoleEquipmentCard extends StatefulWidget {
  const ConsoleEquipmentCard({
    super.key,
    required this.label,
    required this.status,
    required this.icon,
    required this.onTap,
    this.readOnly = false,
    this.active = false,
  });
  final String label;
  final String status;
  final IconData icon;
  final VoidCallback? onTap;
  final bool readOnly;

  /// Device is confirmed on/running; tints the tile with the accent.
  final bool active;

  @override
  State<ConsoleEquipmentCard> createState() => _ConsoleEquipmentCardState();
}

class _ConsoleEquipmentCardState extends State<ConsoleEquipmentCard> {
  bool _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final active = widget.active && enabled;
    final iconColor = active
        ? ConsoleStyle.accent
        : enabled
        ? ConsoleStyle.text
        : ConsoleStyle.faint;
    final statusColor = active
        ? ConsoleStyle.accent
        : enabled && !widget.readOnly
        ? ConsoleStyle.text
        : ConsoleStyle.muted;
    final trailing = widget.readOnly
        ? Icons.lock_outline
        : enabled
        ? Icons.chevron_right
        : null;
    return Semantics(
      button: enabled,
      label:
          '${widget.label}, ${widget.status}${widget.readOnly ? ', read only' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _press(true) : null,
        onTapUp: enabled ? (_) => _press(false) : null,
        onTapCancel: () => _press(false),
        child: AnimatedScale(
          scale: _pressed ? .97 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _pressed
                  ? ConsoleStyle.pressed
                  : active
                  ? ConsoleStyle.accentDim
                  : ConsoleStyle.surface,
              borderRadius: BorderRadius.circular(ConsoleStyle.controlRadius),
              border: Border(
                top: BorderSide(
                  color: active
                      ? ConsoleStyle.accent.withValues(alpha: .35)
                      : ConsoleStyle.border,
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 80;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? 8 : 14,
                    12,
                    compact ? 8 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(widget.icon, size: 20, color: iconColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                color: ConsoleStyle.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              widget.status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 16 : 19,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                          if (trailing != null)
                            Icon(
                              trailing,
                              size: widget.readOnly ? 16 : 20,
                              color: ConsoleStyle.faint,
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
