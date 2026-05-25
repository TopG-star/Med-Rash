import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/medrash_http_client.dart';
import '../models/session_info.dart';
import 'session_repository.dart';

class NetlifySupabaseSessionRepository implements SessionRepository {
  NetlifySupabaseSessionRepository({
    required MedRashHttpClient httpClient,
    AuthStateManager? authStateManager,
    SessionRepository? fallback,
  })  : _fallback = fallback ?? InMemorySessionRepository(),
        _httpClient = httpClient,
        _authStateManager = authStateManager;

  final SessionRepository _fallback;
  final MedRashHttpClient _httpClient;
  final AuthStateManager? _authStateManager;

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
      final Map<String, Object?> payload = <String, Object?>{'joinCode': normalized};
      // Best-effort: attach identity so the admin Live view can count this
      // scan even if the participant never starts/submits an attempt. Identity
      // is optional on the server; missing values must NOT break the scan.
      final String? participantId = _authStateManager?.participantId;
      final String? deviceInstallId = _authStateManager?.deviceId;
      if (participantId != null && participantId.isNotEmpty) {
        payload['participantId'] = participantId;
        if (deviceInstallId != null && deviceInstallId.isNotEmpty) {
          payload['deviceInstallId'] = deviceInstallId;
        }
      }

      final Map<String, dynamic> response = await _httpClient.postJson(
        'session-resolve',
        payload,
      );
      return _parseSessionFromResponse(response);
    } on MedRashGateException catch (error) {
      throw StateError(_describeGateFailure(error, normalized));
    }
  }

  /// Map the server's structured error envelope to a participant-friendly
  /// message. Falls back to a generic copy only when the server returned
  /// no recognised code AND no human-readable message — that way ops can
  /// see the real cause in console.error / Netlify logs while participants
  /// still get a helpful hint instead of "Unable to join session right now".
  String _describeGateFailure(MedRashGateException error, String joinCode) {
    final String serverMessage = (error.body['message'] as String? ?? '').trim();
    switch (error.code) {
      case 'SESSION_NOT_FOUND':
        return 'Session code $joinCode not found. Verify the code with the host and try again.';
      case 'SESSION_QUIZ_MISSING':
        return 'This session is not playable yet (the quiz is missing or inactive). Ask the host to relink it.';
      case 'SESSION_RESOLVE_QUERY_FAILED':
      case 'SESSION_RESOLVE_FAILED':
        return 'Session lookup is failing right now. Please retry in a moment.';
      case 'RATE_LIMITED':
        return 'Too many session lookups. Wait a few seconds and try again.';
      case 'BAD_REQUEST':
        return serverMessage.isNotEmpty
            ? serverMessage
            : 'That session code looks malformed. Please re-scan or re-type it.';
    }
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'This app build is not authorised to look up sessions. Contact support.';
    }
    if (serverMessage.isNotEmpty) {
      return serverMessage;
    }
    return 'Unable to resolve session right now. Please retry shortly.';
  }
}
