import 'dart:async';
import 'dart:developer' as developer;
import 'dart:js_interop';

import 'turnstile_token_provider.dart';

/// Slice A2 phase 3b — web implementation.
///
/// Calls the JS shim installed by `web/index.html`:
///
/// ```js
/// window.medrashTurnstileExecute(siteKey: string): Promise<string|null>
/// ```
///
/// The shim handles the invisible widget lifecycle (lazy-load script,
/// render hidden div on first call, `turnstile.execute()` to obtain a
/// fresh single-use token). If anything fails — script load error, widget
/// timeout, user blocked by Cloudflare — the shim resolves to `null` and
/// `DeviceTokenStore` then falls through to the legacy gate-key bootstrap.
TurnstileTokenProvider createPlatformTurnstileTokenProvider({
  required String siteKey,
  Duration timeout = const Duration(seconds: 10),
}) {
  if (siteKey.trim().isEmpty) {
    return StaticTurnstileTokenProvider(null);
  }
  return _WebTurnstileTokenProvider(siteKey: siteKey, timeout: timeout);
}

@JS('medrashTurnstileExecute')
external JSPromise<JSAny?> _medrashTurnstileExecute(JSString siteKey);

class _WebTurnstileTokenProvider implements TurnstileTokenProvider {
  _WebTurnstileTokenProvider({
    required this.siteKey,
    required this.timeout,
  });

  final String siteKey;
  final Duration timeout;

  @override
  Future<String?> fetchToken() async {
    try {
      final JSAny? result = await _medrashTurnstileExecute(siteKey.toJS)
          .toDart
          .timeout(timeout);
      if (result == null) {
        return null;
      }
      final String token = (result as JSString).toDart;
      return token.isEmpty ? null : token;
    } on TimeoutException {
      developer.log(
        'Turnstile execute timed out after ${timeout.inSeconds}s',
        name: 'TurnstileTokenProvider',
      );
      return null;
    } catch (error, stack) {
      developer.log(
        'Turnstile execute threw — falling back to gate key',
        name: 'TurnstileTokenProvider',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }
}
