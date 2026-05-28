import 'turnstile_token_provider.dart';

/// Non-web (Android, iOS, desktop, VM tests) — Turnstile widget is
/// browser-only, so on these platforms we never fetch a token. The
/// `/device-token` endpoint then falls back to the legacy gate-key
/// bootstrap path during Phase 3b. Phase 3c will replace this with a
/// platform-appropriate attestation challenge.
TurnstileTokenProvider createPlatformTurnstileTokenProvider({
  required String siteKey,
  Duration timeout = const Duration(seconds: 10),
}) =>
    StaticTurnstileTokenProvider(null);
