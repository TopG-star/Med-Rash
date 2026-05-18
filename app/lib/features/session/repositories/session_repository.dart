import '../models/session_info.dart';

abstract class SessionRepository {
  Future<SessionInfo> getFeaturedSession();

  Future<SessionInfo> resolveSessionByJoinCode(String joinCode);
}

class InMemorySessionRepository implements SessionRepository {
  static const SessionInfo _session = SessionInfo(
    sessionId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    joinCode: 'KBTH-CME-2026',
    quizId: 'clexane-vte-masterclass',
    title: 'Korle Bu CME - VTE Master Class',
    category: 'VTE',
    topic: 'Risk recognition and treatment-pathway confidence for DVT and PE scenarios.',
    questionCount: 5,
    timeLimit: '02m',
    host: 'Medical Team Lead',
  );

  @override
  Future<SessionInfo> getFeaturedSession() async {
    return _session;
  }

  @override
  Future<SessionInfo> resolveSessionByJoinCode(String joinCode) async {
    final String normalized = joinCode.trim().toUpperCase();
    if ((_session.joinCode ?? '').toUpperCase() == normalized) {
      return _session;
    }

    throw StateError('Session code not found. Please verify the QR code and try again.');
  }
}