import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Retry policy for [MedRashHttpClient.postJson]. Default is no retry, which
/// preserves the existing single-shot behaviour for every caller that doesn't
/// opt in. Repositories that must survive a flaky cell tower (attempt-submit,
/// profile-sync) pass [RetryPolicy.standard].
///
/// Retries fire only on network exceptions, timeouts, and 5xx responses. 4xx
/// failures are deterministic and rethrown immediately — retrying a 400 just
/// burns the user's battery.
class RetryPolicy {
  const RetryPolicy({
    required this.maxAttempts,
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 4),
  });

  static const RetryPolicy none = RetryPolicy(maxAttempts: 1);

  /// Pilot default: 3 total attempts (1 initial + 2 retries), 500 ms → 1 s → 2 s
  /// with ±20% jitter.
  static const RetryPolicy standard = RetryPolicy(maxAttempts: 3);

  final int maxAttempts;
  final Duration initialBackoff;
  final Duration maxBackoff;

  Duration backoffFor(int attemptIndex, math.Random rng) {
    final int baseMs =
        (initialBackoff.inMilliseconds * (1 << attemptIndex)).clamp(
      initialBackoff.inMilliseconds,
      maxBackoff.inMilliseconds,
    );
    final double jitter = 0.8 + rng.nextDouble() * 0.4; // [0.8, 1.2)
    return Duration(milliseconds: (baseMs * jitter).round());
  }
}

/// Thrown by [MedRashHttpClient] whenever a Netlify function responds with a
/// non-2xx status. Wraps the parsed JSON body (if any) and the status code so
/// repositories can branch on `statusCode` / `body['code']`.
class MedRashGateException implements Exception {
  MedRashGateException({
    required this.functionName,
    required this.statusCode,
    required this.body,
  });

  final String functionName;
  final int statusCode;
  final Map<String, dynamic> body;

  String get code => body['code']?.toString() ?? '';

  @override
  String toString() =>
      'MedRashGateException(fn=$functionName, status=$statusCode, code=$code)';
}

/// Thin, single-purpose HTTP wrapper for every Netlify function call the
/// Flutter app makes. Centralises:
///   * Base URL normalisation
///   * Per-device bearer token injection (Slice A2). The optional
///     [tokenProvider] is awaited before each request; if it returns a
///     non-empty token, the request gets `Authorization: Bearer <token>`.
///   * JSON encode/decode
///   * Structured error logging — every failure is `developer.log`'d with the
///     function name + status before being rethrown. There is exactly one
///     surface that talks to the gateway, so there is exactly one place where
///     silent failures could ever hide.
class MedRashHttpClient {
  MedRashHttpClient({
    required String functionsBaseUrl,
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
    Duration defaultTimeout = const Duration(seconds: 10),
    math.Random? random,
  })  : _baseFunctionsUri = _normalizeFunctionsUri(functionsBaseUrl),
        _httpClient = httpClient ?? http.Client(),
        _tokenProvider = tokenProvider,
        _defaultTimeout = defaultTimeout,
        _random = random ?? math.Random();

  final Uri _baseFunctionsUri;
  final http.Client _httpClient;
  final Future<String?> Function()? _tokenProvider;
  final Duration _defaultTimeout;
  final math.Random _random;

  static Uri _normalizeFunctionsUri(String raw) {
    final String normalized = raw.endsWith('/') ? raw : '$raw/';
    return Uri.parse(normalized);
  }

  Uri _functionUri(String functionName) {
    return _baseFunctionsUri.resolve(functionName);
  }

  Future<Map<String, String>> _buildHeaders() async {
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
    };

    final Future<String?> Function()? provider = _tokenProvider;
    if (provider != null) {
      try {
        final String? token = (await provider())?.trim();
        if (token != null && token.isNotEmpty) {
          headers['authorization'] = 'Bearer $token';
        }
      } catch (error, stack) {
        developer.log(
          'tokenProvider threw; request will go without Authorization header',
          name: 'MedRashHttpClient',
          error: error,
          stackTrace: stack,
        );
      }
    }

    return headers;
  }

  /// POST a JSON payload to the named Netlify function.
  ///
  /// Returns the decoded JSON body on 2xx. Throws [MedRashGateException] for
  /// non-2xx, after logging the failure. Network-layer exceptions (timeouts,
  /// DNS, etc.) are logged and rethrown verbatim so callers can decide their
  /// own recovery.
  ///
  /// [timeout] caps each individual HTTP attempt (default 10s). [retryPolicy]
  /// controls inline retries on network failures, timeouts, and 5xx responses;
  /// defaults to [RetryPolicy.none] to preserve single-shot behaviour for
  /// callers that don't opt in. [idempotencyKey], when provided, is sent as
  /// the `Idempotency-Key` request header so the server can dedupe retries.
  Future<Map<String, dynamic>> postJson(
    String functionName,
    Map<String, Object?> payload, {
    Duration? timeout,
    RetryPolicy retryPolicy = RetryPolicy.none,
    String? idempotencyKey,
  }) async {
    final Uri uri = _functionUri(functionName);
    final Duration perAttemptTimeout = timeout ?? _defaultTimeout;
    final int maxAttempts = math.max(1, retryPolicy.maxAttempts);

    Object? lastError;
    StackTrace? lastStack;

    for (int attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (attempt > 0) {
        final Duration delay = retryPolicy.backoffFor(attempt - 1, _random);
        developer.log(
          'retry $attempt/${maxAttempts - 1} after ${delay.inMilliseconds}ms',
          name: 'MedRashHttpClient.$functionName',
        );
        await Future<void>.delayed(delay);
      }

      final Map<String, String> headers = await _buildHeaders();
      if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
        headers['idempotency-key'] = idempotencyKey;
      }
      // P1.3 — mint a fresh X-Request-ID per attempt so server-side logs
      // can correlate a retry separately from its predecessor. 16 hex
      // chars match the server's mintRequestId() shape.
      headers['x-request-id'] = _mintRequestId();

      http.Response response;
      try {
        response = await _httpClient
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(perAttemptTimeout);
      } on TimeoutException catch (error, stack) {
        lastError = error;
        lastStack = stack;
        developer.log(
          'timeout after ${perAttemptTimeout.inMilliseconds}ms (attempt ${attempt + 1}/$maxAttempts)',
          name: 'MedRashHttpClient.$functionName',
          error: error,
        );
        continue;
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        developer.log(
          'network failure (attempt ${attempt + 1}/$maxAttempts)',
          name: 'MedRashHttpClient.$functionName',
          error: error,
          stackTrace: stack,
        );
        continue;
      }

      Map<String, dynamic> body = <String, dynamic>{};
      if (response.body.trim().isNotEmpty) {
        try {
          final Object? decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            body = decoded;
          }
        } catch (error, stack) {
          developer.log(
            'response body not JSON',
            name: 'MedRashHttpClient.$functionName',
            error: error,
            stackTrace: stack,
          );
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      }

      // 5xx is retriable; 4xx is deterministic — fail fast.
      if (response.statusCode >= 500 && attempt + 1 < maxAttempts) {
        lastError = MedRashGateException(
          functionName: functionName,
          statusCode: response.statusCode,
          body: body,
        );
        developer.log(
          'gate returned ${response.statusCode} (attempt ${attempt + 1}/$maxAttempts) — will retry',
          name: 'MedRashHttpClient.$functionName',
          error: body['code'] ?? body['error'] ?? response.body,
        );
        continue;
      }

      developer.log(
        'gate returned ${response.statusCode}',
        name: 'MedRashHttpClient.$functionName',
        error: body['code'] ?? body['error'] ?? response.body,
      );
      throw MedRashGateException(
        functionName: functionName,
        statusCode: response.statusCode,
        body: body,
      );
    }

    // Exhausted retries on network/timeout/5xx. Rethrow the last error so
    // callers can route it to the outbox or surface a banner.
    if (lastError is Exception) {
      Error.throwWithStackTrace(lastError as Object, lastStack ?? StackTrace.current);
    }
    throw lastError ?? StateError('postJson failed without an error');
  }

  /// P1.3 — mint a 16-hex-char request id (matches the server's shape in
  /// admin/src/lib/request-id.ts so logs are uniform across runtimes).
  String _mintRequestId() {
    final buffer = StringBuffer();
    for (int i = 0; i < 8; i += 1) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
