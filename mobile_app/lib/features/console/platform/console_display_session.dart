import 'package:flutter/services.dart';

abstract interface class ConsoleDisplaySession {
  Future<void> enter();
  Future<void> exit();
}

/// Native adapter saves/restores the activity's actual prior display settings.
/// Calls are serialized, including disposal while entry is still in flight.
class AndroidConsoleDisplaySession implements ConsoleDisplaySession {
  static const _channel = MethodChannel('com.aqualogic.mobile/console_display');
  Future<void> _pending = Future.value();
  Future<void> _call(String method) {
    _pending = _pending.then((_) async {
      try {
        await _channel.invokeMethod<void>(method);
      } on MissingPluginException {
        /* Widget tests / non-Android preview. */
      } on PlatformException {
        /* The layout remains usable if OS declines. */
      }
    });
    return _pending;
  }

  @override
  Future<void> enter() => _call('enter');
  @override
  Future<void> exit() => _call('exit');
}
