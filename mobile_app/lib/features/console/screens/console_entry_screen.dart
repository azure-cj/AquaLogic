import 'package:flutter/material.dart';
import 'package:aqualogic/app/console/console_repository_scope.dart';
import 'tank_console_screen.dart';

class ConsoleEntryScreen extends StatefulWidget {
  const ConsoleEntryScreen({
    super.key,
    required this.createRepository,
    this.onActiveChanged,
  });
  final ConsoleRepositoryFactory createRepository;
  final ValueChanged<bool>? onActiveChanged;
  @override
  State<ConsoleEntryScreen> createState() => _ConsoleEntryScreenState();
}

class _ConsoleEntryScreenState extends State<ConsoleEntryScreen> {
  bool _entering = false;
  Future<void> _enter() async {
    if (_entering) return;
    setState(() => _entering = true);
    widget.onActiveChanged?.call(true);
    final repository = widget.createRepository();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              TankConsoleScreen(repository: repository, ownsRepository: true),
        ),
      );
    } finally {
      widget.onActiveChanged?.call(false);
      if (mounted) setState(() => _entering = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tank Console')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/images/aqualogic_icon.png',
                  height: 56,
                  width: 56,
                ),
                const SizedBox(height: 20),
                const Text(
                  'AquaLogic Tank Console',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Use this device as the local command center for an aquarium.',
                  style: TextStyle(fontSize: 18, height: 1.4),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Tank 01',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('Prototype · simulated data'),
                const SizedBox(height: 8),
                const Text(
                  'This preview uses simulated readings and controls. No ESP32 is connected. Pumps are read-only.',
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('enter-console'),
                    onPressed: _entering ? null : _enter,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    child: const Text('Enter Console Mode'),
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
