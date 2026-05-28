class AppConfig {
  const AppConfig._();

  static const String functionsBaseUrl = String.fromEnvironment(
    'MEDRASH_FUNCTIONS_BASE_URL',
    defaultValue: 'http://localhost:8888/.netlify/functions/',
  );

  static const String gateApiKey = String.fromEnvironment(
    'MEDRASH_GATE_API_KEY',
    defaultValue: '',
  );

  /// Cloudflare Turnstile site key (public). When non-empty AND running on
  /// Flutter web, the Turnstile widget is used as the bootstrap challenge
  /// for `/device-token` (Slice A2 phase 3b). When empty, the legacy
  /// `MEDRASH_GATE_API_KEY` header is the bootstrap. Phase 3c drops the
  /// gate-key path entirely.
  static const String turnstileSiteKey = String.fromEnvironment(
    'MEDRASH_TURNSTILE_SITE_KEY',
    defaultValue: '',
  );

  /// When true, hitting a `/session/<code>` deep link without a bound
  /// profile silently mints a guest profile and lands on the session page
  /// instead of bouncing through `/join`. Toggled per build with
  /// `--dart-define=MEDRASH_QR_FAST_JOIN=true`.
  static const bool qrFastJoin = bool.fromEnvironment(
    'MEDRASH_QR_FAST_JOIN',
    defaultValue: false,
  );
}

