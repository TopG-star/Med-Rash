/// Extracts the canonical session join code from arbitrary QR payloads.
///
/// Hosts print QR codes that may encode any of:
///   * a bare join code, e.g. `ABCD`
///   * a deep link, e.g. `https://medrash.app/session/ABCD`
///   * a session-resolve link with a `code` / `joinCode` query param,
///     e.g. `https://medrash.app/session?code=ABCD`
///   * the forced-onboarding wrapper, e.g.
///     `https://medrash.app/join?next=/session/ABCD`
///
/// Returns `null` when the payload is empty, malformed, or carries no
/// recoverable code.
String? parseJoinCodeFromQr(String? raw) {
  if (raw == null) {
    return null;
  }
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  // Anything that doesn't look like a URL is treated as the code itself.
  // A bare code can be alphanumeric plus separators; we just sanity-check
  // that there's no whitespace inside it.
  if (!trimmed.contains('://') && !trimmed.startsWith('/')) {
    if (trimmed.contains(RegExp(r'\s'))) {
      return null;
    }
    return trimmed;
  }

  Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } on FormatException {
    return null;
  }

  final String? fromPath = _extractCodeFromPath(uri.pathSegments);
  if (fromPath != null) {
    return fromPath;
  }

  for (final String key in const <String>['code', 'joinCode']) {
    final String? value = uri.queryParameters[key];
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }

  // /join?next=/session/ABCD style wrappers from Slice 1.
  final String? next = uri.queryParameters['next'];
  if (next != null && next.trim().isNotEmpty) {
    return parseJoinCodeFromQr(next);
  }

  return null;
}

String? _extractCodeFromPath(List<String> segments) {
  for (int i = 0; i < segments.length; i++) {
    if (segments[i] == 'session' && i + 1 < segments.length) {
      final String candidate = Uri.decodeComponent(segments[i + 1]).trim();
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }
  }
  return null;
}
