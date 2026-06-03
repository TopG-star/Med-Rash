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

  /// P7 — Navii avatars. Off by default; flip per build with
  /// `--dart-define=MEDRASH_ENABLE_NAVII_AVATARS=true` once the backend
  /// function is deployed and a smoke test passes. When false, every
  /// `NaviiAvatarSpec` short-circuits to its monogram fallback.
  static const bool enableNaviiAvatars = bool.fromEnvironment(
    'MEDRASH_ENABLE_NAVII_AVATARS',
    defaultValue: false,
  );

  /// P7.5 — cache-bust key appended to the avatar URL (`&v=<value>`).
  /// Bump this on every `@usenavii/core` upgrade (or any change that alters
  /// the rendered SVG) so existing devices fetch fresh bytes instead of
  /// serving stale entries from `flutter_cache_manager`. Empty value
  /// disables the `v=` query param entirely.
  static const String naviiVersion = String.fromEnvironment(
    'MEDRASH_NAVII_VERSION',
    defaultValue: '0.7.0',
  );

  /// P0.3 — fail-fast at boot for hosted builds.
  ///
  /// In `development` we accept the localhost defaults so `flutter run` keeps
  /// working out of the box. In any other Sentry environment we require
  /// production-grade values to be baked in via `--dart-define=...` (see
  /// `app/scripts/build-web.sh`). Missing values throw [StateError] before
  /// the first widget is built, which is loud and obvious in Sentry rather
  /// than silently 5xx-ing on the first network call.
  static void validateOrThrow(String sentryEnvironment) {
    if (sentryEnvironment == 'development') return;
    final List<String> missing = <String>[];
    if (functionsBaseUrl.isEmpty ||
        functionsBaseUrl.startsWith('http://localhost')) {
      missing.add('MEDRASH_FUNCTIONS_BASE_URL');
    }
    if (turnstileSiteKey.isEmpty) {
      missing.add('MEDRASH_TURNSTILE_SITE_KEY');
    }
    if (missing.isNotEmpty) {
      throw StateError(
        'MedRash AppConfig is missing required build-time defines for '
        '"$sentryEnvironment": ${missing.join(', ')}. Re-run the build with '
        '--dart-define for each.',
      );
    }
  }
}

