import 'turnstile_token_provider_stub.dart'
    if (dart.library.js_interop) 'turnstile_token_provider_web.dart';

/// Slice A2 phase 3b — fetches a fresh Cloudflare Turnstile token for the
/// bootstrap call to `/device-token`.
///
/// One token per mint attempt. Tokens are single-use and expire within ~5
/// minutes server-side, so we never cache them client-side.
///
/// Implementations:
///   * `turnstile_token_provider_web.dart` — calls the JS shim in
///     `web/index.html` (`window.medrashTurnstileExecute()`).
///   * `turnstile_token_provider_stub.dart` — non-web platforms (Android,
///     iOS, tests). Always returns null; `DeviceTokenStore` then falls
///     through to the legacy gate-key bootstrap path (Phase 3b only).
abstract class TurnstileTokenProvider {
  Future<String?> fetchToken();

  factory TurnstileTokenProvider.platformDefault({
    required String siteKey,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      createPlatformTurnstileTokenProvider(siteKey: siteKey, timeout: timeout);
}

/// Test/stub implementation. Always returns the same configured value
/// (default: null). Used in `init_core.dart` when the site key is empty
/// AND in unit tests via [DeviceTokenStore.turnstileTokenProvider].
class StaticTurnstileTokenProvider implements TurnstileTokenProvider {
  StaticTurnstileTokenProvider([this._token]);

  final String? _token;

  @override
  Future<String?> fetchToken() async => _token;
}
