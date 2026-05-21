import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

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
///   * Gate API key header injection
///   * JSON encode/decode
///   * Structured error logging — every failure is `developer.log`'d with the
///     function name + status before being rethrown. There is exactly one
///     surface that talks to the gateway, so there is exactly one place where
///     silent failures could ever hide.
class MedRashHttpClient {
  MedRashHttpClient({
    required String functionsBaseUrl,
    String? gateApiKey,
    http.Client? httpClient,
  })  : _baseFunctionsUri = _normalizeFunctionsUri(functionsBaseUrl),
        _gateApiKey = gateApiKey,
        _httpClient = httpClient ?? http.Client();

  final Uri _baseFunctionsUri;
  final String? _gateApiKey;
  final http.Client _httpClient;

  static Uri _normalizeFunctionsUri(String raw) {
    final String normalized = raw.endsWith('/') ? raw : '$raw/';
    return Uri.parse(normalized);
  }

  Uri _functionUri(String functionName) {
    return _baseFunctionsUri.resolve(functionName);
  }

  Map<String, String> _buildHeaders() {
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
    };

    final String gateKey = _gateApiKey?.trim() ?? '';
    if (gateKey.isNotEmpty) {
      headers['x-medrash-gate-key'] = gateKey;
    }

    return headers;
  }

  /// POST a JSON payload to the named Netlify function.
  ///
  /// Returns the decoded JSON body on 2xx. Throws [MedRashGateException] for
  /// non-2xx, after logging the failure. Network-layer exceptions (timeouts,
  /// DNS, etc.) are logged and rethrown verbatim so callers can decide their
  /// own recovery.
  Future<Map<String, dynamic>> postJson(
    String functionName,
    Map<String, Object?> payload,
  ) async {
    final Uri uri = _functionUri(functionName);

    http.Response response;
    try {
      response = await _httpClient.post(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(payload),
      );
    } catch (error, stack) {
      developer.log(
        'network failure',
        name: 'MedRashHttpClient.$functionName',
        error: error,
        stackTrace: stack,
      );
      rethrow;
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
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

    return body;
  }
}
