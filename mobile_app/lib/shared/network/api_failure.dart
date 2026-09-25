enum ApiFailureKind {
  validation,
  business,
  unauthenticated,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  server,
  timeout,
  networkUnavailable,
  unknown,
}

/// A safe, normalized failure from the mobile API boundary.
///
/// `message` is suitable for application presentation. Raw FastAPI payloads,
/// exception strings, request bodies, and credentials are never surfaced.
class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    required this.message,
    this.statusCode,
    this.retryable = false,
    this.retryAfter,
    this.fieldErrors = const {},
  });

  final ApiFailureKind kind;
  final String message;
  final int? statusCode;
  final bool retryable;
  final Duration? retryAfter;
  final Map<String, String> fieldErrors;

  bool get isUnauthenticated => kind == ApiFailureKind.unauthenticated;

  factory ApiFailure.fromStatus(
    int statusCode, {
    Map<String, String> headers = const {},
    Object? responseBody,
  }) {
    final normalizedHeaders = <String, String>{
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final retryAfter = _parseRetryAfter(normalizedHeaders['retry-after']);

    final kind = switch (statusCode) {
      400 => ApiFailureKind.business,
      401 => ApiFailureKind.unauthenticated,
      403 => ApiFailureKind.forbidden,
      404 => ApiFailureKind.notFound,
      409 => ApiFailureKind.conflict,
      422 => ApiFailureKind.validation,
      429 => ApiFailureKind.rateLimited,
      >= 500 => ApiFailureKind.server,
      _ => ApiFailureKind.unknown,
    };

    final message = switch (kind) {
      ApiFailureKind.business => 'That request could not be completed.',
      ApiFailureKind.unauthenticated => 'Your sign-in session has expired.',
      ApiFailureKind.forbidden => 'You do not have access to this action.',
      ApiFailureKind.notFound => 'That AquaLogic item could not be found.',
      ApiFailureKind.conflict =>
        'That change conflicts with the current state.',
      ApiFailureKind.validation => 'Check the information and try again.',
      ApiFailureKind.rateLimited => 'Too many requests. Try again shortly.',
      ApiFailureKind.server => 'AquaLogic is temporarily unavailable.',
      ApiFailureKind.timeout => 'AquaLogic did not respond in time.',
      ApiFailureKind.networkUnavailable => 'Could not connect to AquaLogic.',
      ApiFailureKind.unknown => 'Something went wrong. Try again.',
    };

    return ApiFailure(
      kind: kind,
      statusCode: statusCode,
      message: message,
      retryable:
          kind == ApiFailureKind.rateLimited || kind == ApiFailureKind.server,
      retryAfter: retryAfter,
      fieldErrors: _safeFieldErrors(responseBody),
    );
  }

  factory ApiFailure.timeout() => const ApiFailure(
    kind: ApiFailureKind.timeout,
    message: 'AquaLogic did not respond in time. Try again.',
    retryable: true,
  );

  factory ApiFailure.networkUnavailable() => const ApiFailure(
    kind: ApiFailureKind.networkUnavailable,
    message: "Can't connect to AquaLogic. Check your connection and try again.",
    retryable: true,
  );

  factory ApiFailure.secureStorage() => const ApiFailure(
    kind: ApiFailureKind.unknown,
    message: 'A secure sign-in session could not be saved on this device.',
    retryable: true,
  );

  static Duration? _parseRetryAfter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    final date = DateTime.tryParse(value);
    if (date == null) return null;
    final remaining = date.toUtc().difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static Map<String, String> _safeFieldErrors(Object? responseBody) {
    if (responseBody is! Map<String, dynamic>) return const {};
    final detail = responseBody['detail'];
    if (detail is! List) return const {};

    final errors = <String, String>{};
    for (final item in detail) {
      if (item is! Map) continue;
      final location = item['loc'];
      final field = location is List && location.isNotEmpty
          ? location.last.toString()
          : '';
      final message = item['msg'];
      if (_safeFieldNames.contains(field) && message is String) {
        // Pydantic's `msg` does not include its `input` value. Only known
        // fields are retained; raw payloads and arbitrary backend text are not.
        errors[field] = _safeValidationMessage(field, message);
      }
    }
    return Map.unmodifiable(errors);
  }

  static const _safeFieldNames = <String>{
    'email',
    'password',
    'current_password',
    'new_password',
  };

  static String _safeValidationMessage(String field, String message) {
    if (field == 'email') return 'Enter a valid email address.';
    if (field == 'new_password' && message.contains('at least')) {
      return 'Use at least 12 characters.';
    }
    if (field == 'new_password' && message.contains('at most')) {
      return 'Use no more than 128 characters.';
    }
    if (field == 'password' || field == 'current_password') {
      return 'Enter your password.';
    }
    return 'Check this field.';
  }

  @override
  String toString() => 'ApiFailure(${kind.name}, status: $statusCode)';
}
