import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/session_info.dart';
import 'session_repository.dart';

class NetlifySupabaseSessionRepository implements SessionRepository {
  NetlifySupabaseSessionRepository({
    required String functionsBaseUrl,
    SessionRepository? fallback,
    http.Client? httpClient,
    String? gateApiKey,
  })  : _fallback = fallback ?? InMemorySessionRepository(),
        _httpClient = httpClient ?? http.Client(),
        _gateApiKey = gateApiKey,
        _baseFunctionsUri = _normalizeFunctionsUri(functionsBaseUrl);

  final SessionRepository _fallback;
  final http.Client _httpClient;
  final String? _gateApiKey;
  final Uri _baseFunctionsUri;

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

  Future<Map<String, dynamic>> _postJson(
    String functionName,
    Map<String, Object?> payload,
  ) async {
    final http.Response response = await _httpClient.post(
      _functionUri(functionName),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );

    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _GateHttpException(statusCode: response.statusCode, body: body);
    }

    return body;
  }

  SessionInfo _parseSessionFromResponse(Map<String, dynamic> response) {
    final Object? rawSession = response['session'];
    if (rawSession is! Map<String, dynamic>) {
      throw StateError('Session payload is missing.');
    }

    final int questionCount = (rawSession['questionCount'] as int?) ?? 5;
    final String timeLimit = (rawSession['timeLimit'] as String? ?? '').trim();

    return SessionInfo(
      sessionId: rawSession['sessionId'] as String?,
      joinCode: rawSession['joinCode'] as String?,
      quizId: (rawSession['quizId'] as String? ?? '').trim(),
      title: (rawSession['title'] as String? ?? '').trim(),
      category: (rawSession['category'] as String? ?? '').trim(),
      topic: (rawSession['topic'] as String? ?? '').trim(),
      questionCount: questionCount,
      timeLimit: timeLimit.isNotEmpty ? timeLimit : '02m',
      host: (rawSession['host'] as String? ?? 'Medical Team Lead').trim(),
    );
  }

  @override
  Future<SessionInfo> getFeaturedSession() {
    return _fallback.getFeaturedSession();
  }

  @override
  Future<SessionInfo> resolveSessionByJoinCode(String joinCode) async {
    final String normalized = joinCode.trim();
    if (normalized.isEmpty) {
      throw StateError('Session code is required.');
    }

    try {
      final Map<String, dynamic> response = await _postJson(
        'session-resolve',
        <String, Object?>{'joinCode': normalized},
      );
      return _parseSessionFromResponse(response);
    } on _GateHttpException catch (error) {
      if (error.statusCode == 429 || error.body['code'] == 'RATE_LIMITED') {
        throw StateError('Too many session lookups right now. Please retry shortly.');
      }
      if (error.statusCode == 404) {
        throw StateError('Session code not found. Please verify the QR code and try again.');
      }
      throw StateError('Unable to resolve session right now. Please retry shortly.');
    }
  }
}

class _GateHttpException implements Exception {
  _GateHttpException({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final Map<String, dynamic> body;
}
