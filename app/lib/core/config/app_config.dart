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

  /// When true, hitting a `/session/<code>` deep link without a bound
  /// profile silently mints a guest profile and lands on the session page
  /// instead of bouncing through `/join`. Toggled per build with
  /// `--dart-define=MEDRASH_QR_FAST_JOIN=true`.
  static const bool qrFastJoin = bool.fromEnvironment(
    'MEDRASH_QR_FAST_JOIN',
    defaultValue: false,
  );
}

