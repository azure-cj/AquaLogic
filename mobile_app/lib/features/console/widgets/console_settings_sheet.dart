import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../data/console_repository.dart';
import 'console_style.dart';
import 'console_status_bar.dart';

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
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Console settings',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Close settings',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '${widget.controller.state?.tankName ?? 'Tank 01'} · Console Mode ON',
            style: const TextStyle(fontSize: 17),
          ),
          const Text(
            'Prototype · simulated data',
            style: TextStyle(color: ConsoleStyle.accent),
          ),
          const SizedBox(height: 12),
          if (widget.controller.state case final state?) ...[
            ConsoleStatusBar(state: state),
            const SizedBox(height: 12),
          ],
          const Text(
            'LOCAL controls the tank. CLOUD supports history, remote access, analytics, alerts and synchronization.',
            style: TextStyle(color: ConsoleStyle.muted, height: 1.4),
          ),
          if (widget.controller.hasScenarios) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<ConsoleScenario>(
              key: const ValueKey('console-scenario-picker'),
              initialValue: _selected,
              dropdownColor: ConsoleStyle.surface,
              decoration: const InputDecoration(
                labelText: 'Prototype scenario',
                filled: false,
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
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: widget.onExit,
            child: const Text('Exit Console Mode'),
          ),
        ],
      ),
    ),
  );
}
