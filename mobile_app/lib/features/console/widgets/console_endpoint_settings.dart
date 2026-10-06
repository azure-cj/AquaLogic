import 'package:flutter/material.dart';
import '../data/console_configuration_store.dart';
import '../data/console_repository.dart';

/// Shared by initial setup and the mounted console's settings panel.
class ConsoleEndpointSettings extends StatefulWidget {
  const ConsoleEndpointSettings({
    super.key,
    this.repository,
    this.store,
    this.createRepository,
  });
  final ConsoleRepository? repository;
  final ConsoleConfigurationStore? store;
  final ConsoleRepository Function()? createRepository;
  @override
  State<ConsoleEndpointSettings> createState() =>
      _ConsoleEndpointSettingsState();
}

class _ConsoleEndpointSettingsState extends State<ConsoleEndpointSettings> {
  final _host = TextEditingController();
  late final ConsoleConfigurationStore _store =
      widget.store ?? SecureConsoleConfigurationStore();
  String? _message;
  bool _busy = true;
  bool _okay = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final host = widget.repository?.configuredHost ?? await _store.readHost();
      if (!mounted) return;
      _host.text = host ?? '';
    } catch (_) {
      if (mounted) {
        _message =
            'Unable to read local settings. You can save the host again.';
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save({bool test = false}) async {
    setState(() {
      _busy = true;
      _message = null;
      _okay = false;
    });
    ConsoleRepository? temporary;
    try {
      final endpoint = ConsoleEndpoint.parse(_host.text);
      final repository = widget.repository;
      if (repository != null) {
        await repository.configureHost(endpoint.host);
      } else {
        await _store.writeHost(endpoint.host);
      }
      if (test) {
        final target =
            repository ?? (temporary = widget.createRepository?.call());
        if (target == null) throw StateError('Connection tester unavailable');
        final connected = await target.testConnection();
        final state = await target.getState();
        _okay = connected;
        _message = connected
            ? (state.connectionMessage != null
                  ? 'ESP32 reached. Some data is unavailable; check equipment status.'
                  : 'ESP32 connection verified. Local telemetry and equipment status are reachable. Live controls remain disabled.')
            : state.connectionMessage ??
                  'Connection not verified. Check the address and local Wi-Fi.';
      } else {
        _okay = true;
        _message = 'ESP32 host saved on this device.';
      }
    } on FormatException catch (error) {
      _message = error.message;
    } catch (_) {
      _message = 'Unable to save or test the ESP32 host. Try again.';
    } finally {
      await temporary?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _host,
        enabled: !_busy,
        key: const ValueKey('console-host'),
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'ESP32 IP / local host',
          hintText: 'aqualogic.local',
          helperText: 'Private Wi-Fi address or local hostname · HTTP port 80',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save host'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _save(test: true),
            child: Text(_busy ? 'Please wait…' : 'Test Connection'),
          ),
        ],
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _message!,
            style: TextStyle(
              color: _okay
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
    ],
  );
}
