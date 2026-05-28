class AppConfig {
  const AppConfig._();

  static const String functionsBaseUrl = String.fromEnvironment(
    'MEDRASH_FUNCTIONS_BASE_URL',
    defaultValue: 'http://localhost:8888/.netlify/functions/',
  );

  /// Cloudflare Turnstile site key (public). Required on Flutter web for the
  /// `/device-token` bootstrap challenge (Slice A2 phase 3c). Empty means the
  /// widget will not load and mint will fail; non-web platforms ignore this.
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

