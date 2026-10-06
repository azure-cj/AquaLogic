import 'dart:async';
import '../models/console_command.dart';
import '../models/console_state.dart';
import 'console_repository.dart';
import 'console_configuration_store.dart';
import 'console_http_transport.dart';
import 'esp32_console_parser.dart';
import 'esp32_console_commands.dart';

/// Local telemetry and single-shot commands; firmware reports are authoritative.
class Esp32ConsoleRepository extends ConsoleRepository {
  Esp32ConsoleRepository({
    ConsoleConfigurationStore? configurationStore,
    ConsoleHttpTransport? transport,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 2),
    this.staleAfter = const Duration(seconds: 10),
    this.commandConfirmationWindow = const Duration(seconds: 12),
  }) : _store = configurationStore ?? SecureConsoleConfigurationStore(),
       _transport = transport ?? createConsoleHttpTransport(),
       _clock = clock ?? DateTime.now;
  final ConsoleConfigurationStore _store;
  final ConsoleHttpTransport _transport;
  final DateTime Function() _clock;
  final Duration pollInterval;
  final Duration staleAfter;
  final Duration commandConfirmationWindow;
  final _updates = StreamController<ConsoleState>.broadcast();
  ConsoleEndpoint? _endpoint;
  Future<void>? _initialization;
  Future<void>? _inFlight;
  Timer? _timer;
  Timer? _freshnessTimer;
  bool _disposed = false;
  int _listeners = 0;
  ConsoleState _state = _empty();
  final _reports = <String, Map<String, dynamic>?>{};
  Future<void>? _wire;
  int _commandGeneration = 0;
  late final _commands = Esp32ConsoleCommands(
    confirmationWindow: commandConfirmationWindow,
    state: () => _state,
    notify: () => _emit(_state),
    send: (action) {
      final generation = _commandGeneration;
      return _serial(() async {
        if (_disposed || generation != _commandGeneration) {
          throw const ConsoleCommandFailure(mayHaveReachedDevice: false);
        }
        final endpoint = _endpoint;
        if (endpoint == null || _transport is! ConsoleCommandTransport) {
          throw const ConsoleCommandFailure(mayHaveReachedDevice: false);
        }
        return (_transport as ConsoleCommandTransport).sendCommand(
          endpoint.baseUri.resolve(action.path),
        );
      });
    },
    refresh: (action) async {
      final endpoint = _endpoint;
      if (_disposed || endpoint == null) return;
      try {
        await _read(endpoint, action.statusPath);
      } catch (_) {
        _reports[action.statusPath] = null;
      }
      if (!_disposed && endpoint == _endpoint) {
        _emit(
          _state.copyWith(equipment: Esp32ConsoleParser.equipment(_reports)),
        );
      }
    },
  );
  Future<T> _serial<T>(Future<T> Function() work) {
    final result = (_wire ?? Future<void>.value()).then((_) {
      if (_disposed) throw StateError('Console disposed');
      return work();
    });
    _wire = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, dynamic>> _read(ConsoleEndpoint endpoint, String path) =>
      _serial(() async {
        final value = Esp32ConsoleParser.object(
          await _transport.get(endpoint.baseUri.resolve(path)),
        );
        if (!_disposed && endpoint == _endpoint) {
          _reports[path] = value;
          _commands.reconcile(Esp32ConsoleParser.equipment(_reports), path);
        }
        return value;
      });
  static ConsoleState _empty() => const ConsoleState(
    observedAt: null,
    temperature: null,
    ph: null,
    tds: null,
    turbidity: null,
    quality: null,
    localConnected: false,
    cloudConnected: null,
    isSimulated: false,
    localStatus: ConsoleLocalConnection.connecting,
    equipment: ConsoleEquipmentState(
      lightConfirmed: false,
      uvConfirmed: false,
      feederConfirmed: false,
      pumpAStatus: 'UNKNOWN',
      pumpBStatus: 'UNKNOWN',
    ),
  );
  @override
  bool get isReadOnly => _transport is! ConsoleCommandTransport;
  @override
  bool get supportsPumpControls => !isReadOnly;
  @override
  bool get supportsLocalConfiguration => true;
  @override
  String? get configuredHost => _endpoint?.host;

  Future<void> _initialize() => _initialization ??= (() async {
    try {
      final host = await _store.readHost();
      if (host != null) _endpoint = ConsoleEndpoint.parse(host);
    } catch (_) {
      _emit(
        _snapshot(
          connection: ConsoleLocalConnection.disconnected,
          message: 'Local configuration unavailable. Set the ESP32 host again.',
        ),
      );
    }
  })();
  @override
  Future<ConsoleState> getState() async {
    await _initialize();
    return _state;
  }

  @override
  Stream<ConsoleState> watchState() => Stream.multi((sink) {
    if (_disposed) {
      sink.close();
      return;
    }
    _listeners++;
    sink.add(_state);
    final subscription = _updates.stream.listen(sink.add, onDone: sink.close);
    unawaited(_poll());
    sink.onCancel = () async {
      await subscription.cancel();
      _listeners--;
      if (_listeners == 0) {
        cancelCommands();
        _timer?.cancel();
        _timer = null;
        _freshnessTimer?.cancel();
      }
    };
  }, isBroadcast: true);

  Future<void> _poll() {
    if (_disposed) return Future.value();
    final pending = _inFlight;
    if (pending != null) return pending;
    _timer?.cancel();
    final started = _clock();
    final work = _cycle().whenComplete(() {
      _inFlight = null;
      if (!_disposed && _listeners > 0) {
        final remainder = pollInterval - _clock().difference(started);
        _timer = Timer(
          remainder.isNegative ? Duration.zero : remainder,
          () => unawaited(_poll()),
        );
      }
    });
    _inFlight = work;
    return work;
  }

  Future<void> _cycle() async {
    await _initialize();
    if (_disposed) return;
    final endpoint = _endpoint;
    if (endpoint == null) {
      _emit(
        _snapshot(
          connection: ConsoleLocalConnection.disconnected,
          message: 'Configure the ESP32 host in Console settings.',
        ),
      );
      return;
    }
    final responses = <String, Map<String, dynamic>?>{};
    Object? dataError;
    DateTime? received;
    for (final path in [
      '/data',
      '/led/status',
      '/uv/status',
      '/feeder/status',
      '/syringeA/status',
      '/syringeB/status',
    ]) {
      if (_disposed) return;
      try {
        responses[path] = await _read(endpoint, path);
        if (path == '/data') received = _clock();
      } catch (error) {
        responses[path] = null;
        _reports[path] = null;
        // Avoid six sequential timeouts when the device cannot be reached.
        if (path == '/data') {
          dataError = error;
          break;
        }
      }
    }
    if (_disposed) return;
    final data = responses['/data'];
    if (data == null) {
      final age = _state.observedAt == null
          ? staleAfter
          : _clock().difference(_state.observedAt!);
      _emit(
        _snapshot(
          connection: age >= staleAfter
              ? ConsoleLocalConnection.disconnected
              : ConsoleLocalConnection.degraded,
          message: _readFailureMessage(dataError),
          equipment: _unavailableEquipment(),
        ),
      );
      return;
    }
    final temperature = Esp32ConsoleParser.number(data['temp_c']);
    // DallasTemperature -127 is a disconnected probe, not water temperature.
    final temp = temperature == -127 ? null : temperature;
    final ph = Esp32ConsoleParser.number(data['ph_value']);
    final tds = Esp32ConsoleParser.number(data['tds_ppm']);
    final turbidity = Esp32ConsoleParser.number(data['turbidity_ntu']);
    final equipment = Esp32ConsoleParser.equipment(_reports);
    final complete =
        temp != null &&
        ph != null &&
        tds != null &&
        turbidity != null &&
        equipment.lightConfirmed &&
        equipment.uvConfirmed &&
        equipment.feederConfirmed &&
        equipment.pumpAStatus != 'UNKNOWN' &&
        equipment.pumpBStatus != 'UNKNOWN';
    final hasReading = [temp, ph, tds, turbidity].any((v) => v != null);
    if (!hasReading) {
      final age = _state.observedAt == null
          ? staleAfter
          : _clock().difference(_state.observedAt!);
      _emit(
        _snapshot(
          connection: age >= staleAfter
              ? ConsoleLocalConnection.disconnected
              : ConsoleLocalConnection.degraded,
          message:
              'ESP32 reached, but no usable sensor readings were returned. Confirm the address and AquaLogic firmware. Last known readings are retained.',
          equipment: equipment,
        ),
      );
      return;
    }
    final stale =
        received == null || _clock().difference(received) >= staleAfter;
    _freshnessTimer?.cancel();
    if (hasReading && !stale) {
      _freshnessTimer = Timer(staleAfter - _clock().difference(received), () {
        if (_disposed) return;
        _emit(
          _snapshot(
            connection: ConsoleLocalConnection.disconnected,
            message: 'No recent local update. Showing last known readings.',
            equipment: _unavailableEquipment(),
          ),
        );
      });
    }
    _emit(
      ConsoleState(
        observedAt: hasReading ? received : null,
        temperature: temp,
        ph: ph,
        tds: tds,
        turbidity: turbidity,
        quality: [temp, ph, tds, turbidity].every((v) => v != null)
            ? Esp32ConsoleParser.quality(data['overall_status'])
            : null,
        isSimulated: false,
        telemetryStale: stale,
        cloudConnected: null,
        localConnected: !stale,
        localStatus: complete && !stale
            ? ConsoleLocalConnection.connected
            : ConsoleLocalConnection.degraded,
        connectionMessage: complete
            ? null
            : 'Some readings or equipment states are unavailable.',
        sensorStatuses: {
          for (final name in ['temp', 'ph', 'tds', 'turbidity'])
            if (Esp32ConsoleParser.status(data['${name}_status'])
                case final String value)
              name: value,
        },
        equipment: equipment,
      ),
    );
  }

  static String _readFailureMessage(Object? error) {
    if (error is TimeoutException) {
      return 'ESP32 timed out. Check the address and shared Wi-Fi, then Test Connection again.';
    }
    if (error is ConsoleReadFailure) return error.message;
    if (error is FormatException) {
      return 'ESP32 response was invalid or unexpected. Confirm the address and AquaLogic firmware; use a private Wi-Fi IP.';
    }
    return 'ESP32 unreachable. Check the address and that Android and ESP32 are on the same Wi-Fi.';
  }

  ConsoleEquipmentState _unavailableEquipment() => _state.equipment.copyWith(
    lightConfirmed: false,
    uvConfirmed: false,
    feederConfirmed: false,
    pumpAStatus: 'UNKNOWN',
    pumpBStatus: 'UNKNOWN',
  );

  ConsoleState _snapshot({
    required ConsoleLocalConnection connection,
    String? message,
    ConsoleEquipmentState? equipment,
  }) => ConsoleState(
    observedAt: _state.observedAt,
    temperature: _state.temperature,
    ph: _state.ph,
    tds: _state.tds,
    turbidity: _state.turbidity,
    quality: _state.quality,
    sensorStatuses: _state.sensorStatuses,
    equipment: equipment ?? _state.equipment,
    isSimulated: false,
    cloudConnected: _state.cloudConnected,
    localConnected: connection == ConsoleLocalConnection.connected,
    localStatus: connection,
    connectionMessage: message,
    telemetryStale: true,
  );
  void _emit(ConsoleState value) {
    if (!_disposed) {
      _state = value.copyWith(
        command: _commands.last,
        commands: Map.unmodifiable(_commands.latest),
        uncertainCommands: List.unmodifiable(_commands.uncertain),
      );
      _updates.add(_state);
    }
  }

  @override
  Future<void> configureHost(String host) async {
    final endpoint = ConsoleEndpoint.parse(host);
    await _initialize();
    await _store.writeHost(endpoint.host);
    cancelCommands();
    _timer?.cancel();
    await _inFlight;
    _timer?.cancel();
    if (_disposed) return;
    _endpoint = endpoint;
    _reports.clear();
    _freshnessTimer?.cancel();
    _emit(_empty());
    if (_listeners > 0) {
      _timer = Timer(Duration.zero, () => unawaited(_poll()));
    }
  }

  @override
  Future<bool> testConnection() async {
    await _poll();
    return _state.localConnected && _state.observedAt != null;
  }

  @override
  Future<void> retryLocalConnection() => _poll();
  @override
  Future<ConsoleEquipmentState> getEquipmentState() async => _state.equipment;
  @override
  Future<ConsoleCommand> setLight(bool enabled) =>
      _submit(enabled ? ConsoleAction.lightOn : ConsoleAction.lightOff);
  @override
  Future<ConsoleCommand> setUV(bool enabled) =>
      _submit(enabled ? ConsoleAction.uvOn : ConsoleAction.uvOff);
  @override
  Future<ConsoleCommand> feed() => _submit(ConsoleAction.feed);
  @override
  Future<ConsoleCommand> pump(ConsoleAction action) {
    if (!action.isPump) throw ArgumentError('Expected a pump action');
    return _submit(action);
  }

  @override
  void cancelCommands() {
    _commandGeneration++;
    _commands.cancel();
  }

  Future<ConsoleCommand> _submit(ConsoleAction action) async {
    if (isReadOnly) {
      throw UnsupportedError('This transport supports monitoring only.');
    }
    return _commands.submit(action);
  }

  @override
  Future<ConsoleCommand?> getCommand(String id) async => _commands.get(id);
  @override
  Stream<ConsoleCommand> watchCommand(String id) => Stream.multi((sink) {
    final command = _commands.get(id);
    if (command != null) sink.add(command);
    final sub = _updates.stream.listen((_) {
      final value = _commands.get(id);
      if (value != null) sink.add(value);
    }, onDone: sink.close);
    sink.onCancel = sub.cancel;
  });
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _commandGeneration++;
    _commands.dispose();
    _timer?.cancel();
    _freshnessTimer?.cancel();
    _transport.close();
    // A departing widget/test can pause event delivery. Socket/timer shutdown
    // must not wait for a subscriber to process its final stream event.
    unawaited(_updates.close());
  }
}
