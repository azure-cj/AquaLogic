class RefreshCookieChange {
  const RefreshCookieChange({required this.present, required this.value});

  /// False means the server did not send this cookie in the response.
  final bool present;

  /// Null means the server explicitly cleared it or sent an empty value.
  final String? value;
}

/// Extracts only the AquaLogic refresh value from a Set-Cookie response header.
/// Cookie attributes and unrelated cookies are never persisted.
RefreshCookieChange readRefreshCookie(Map<String, String> headers) {
  String? setCookie;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'set-cookie') {
      setCookie = entry.value;
      break;
    }
  }
  if (setCookie == null) {
    return const RefreshCookieChange(present: false, value: null);
  }

  final match = RegExp(
    r'(?:^|[,;]\s*)aqualogic_refresh=([^;,\s]*)',
  ).firstMatch(setCookie);
  if (match == null) {
    return const RefreshCookieChange(present: false, value: null);
  }

  var value = match.group(1) ?? '';
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  if (value.isEmpty) {
    return const RefreshCookieChange(present: true, value: null);
  }
  return RefreshCookieChange(present: true, value: value);
}
