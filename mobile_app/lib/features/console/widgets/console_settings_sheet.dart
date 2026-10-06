import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../data/console_repository.dart';
import 'console_panel.dart';
import 'console_style.dart';
import 'console_endpoint_settings.dart';

class ConsoleSettingsSheet extends StatefulWidget {
  const ConsoleSettingsSheet({
    super.key,
    required this.controller,
    required this.onExit,
  });
  final ConsoleController controller;
  final VoidCallback onExit;
  @override
  State<ConsoleSettingsSheet> createState() => _ConsoleSettingsSheetState();
}

class _ConsoleSettingsSheetState extends State<ConsoleSettingsSheet> {
  ConsoleScenario? _selected;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: ConsoleStaggerColumn(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConsolePanelHeader(
              icon: Icons.tune_rounded,
              title: 'Console settings',
              subtitle: '${state?.tankName ?? 'Tank 01'} · Console Mode on',
              closeTooltip: 'Close settings',
            ),
            const SizedBox(height: 28),
            const ConsoleSectionLabel('Connections'),
            ConsoleInset(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ConnectionRow(
                    icon: Icons.memory_rounded,
                    title: 'Local ESP32',
                    detail: state?.isSimulated == false
                        ? 'Direct local telemetry and control'
                        : 'Controls the tank equipment',
                    connected: state?.localConnected ?? false,
                    status: state?.isSimulated == false
                        ? state?.connection.name
                        : null,
                  ),
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: ConsoleStyle.hairline,
                  ),
                  _ConnectionRow(
                    icon: Icons.cloud_outlined,
                    title: 'Cloud',
                    detail: 'History, alerts, analytics and sync',
                    connected: state?.cloudConnected,
                  ),
                ],
              ),
            ),
            if (widget.controller.repository.supportsLocalConfiguration) ...[
              const SizedBox(height: 20),
              ConsoleEndpointSettings(repository: widget.controller.repository),
            ],
            if (widget.controller.hasScenarios) ...[
              const SizedBox(height: 24),
              const ConsoleSectionLabel('Prototype scenario'),
              DropdownButtonFormField<ConsoleScenario>(
                key: const ValueKey('console-scenario-picker'),
                initialValue: _selected,
                isExpanded: true,
                dropdownColor: ConsoleStyle.surface,
                borderRadius: BorderRadius.circular(ConsoleStyle.controlRadius),
                hint: const Text(
                  'Choose a simulated scenario',
                  style: TextStyle(color: ConsoleStyle.muted),
                ),
                style: const TextStyle(color: ConsoleStyle.text, fontSize: 15),
                iconEnabledColor: ConsoleStyle.muted,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ConsoleStyle.background.withValues(alpha: .55),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      ConsoleStyle.controlRadius,
                    ),
                    borderSide: const BorderSide(color: ConsoleStyle.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      ConsoleStyle.controlRadius,
                    ),
                    borderSide: const BorderSide(color: ConsoleStyle.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      ConsoleStyle.controlRadius,
                    ),
                    borderSide: const BorderSide(color: ConsoleStyle.accent),
                  ),
                ),
                items: ConsoleScenario.values
                    .map(
                      (scenario) => DropdownMenuItem(
                        value: scenario,
                        child: Text(scenario.label),
                      ),
                    )
                    .toList(),
                onChanged: (scenario) {
                  if (scenario == null) return;
                  setState(() => _selected = scenario);
                  widget.controller.applyScenario(scenario);
                },
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: widget.onExit,
                icon: const Icon(Icons.logout_rounded, size: 20),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ConsoleStyle.text,
                  side: const BorderSide(color: ConsoleStyle.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      ConsoleStyle.controlRadius,
                    ),
                  ),
                ),
                label: const Text('Exit Console Mode'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.connected,
    this.status,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool? connected;
  final String? status;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        ConsoleIconBadge(
          icon: icon,
          active: connected == true && status != 'degraded',
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                detail,
                style: const TextStyle(fontSize: 13, color: ConsoleStyle.muted),
              ),
            ],
          ),
        ),
        Text(
          status ??
              (connected == null
                  ? 'Unknown'
                  : connected == true
                  ? 'Connected'
                  : 'Unavailable'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: connected == true && status != 'degraded'
                ? ConsoleStyle.good
                : ConsoleStyle.warning,
          ),
        ),
      ],
    ),
  );
}
