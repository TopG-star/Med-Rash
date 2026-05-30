import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/infra/medrash_http_client.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/repositories/profile_repository.dart';
import '../models/leaderboard_row.dart';
import '../models/session_leaderboard_row.dart';
import 'leaderboard_repository.dart';

class NetlifySupabaseLeaderboardRepository implements LeaderboardRepository {
  NetlifySupabaseLeaderboardRepository({
    required MedRashHttpClient httpClient,
    required AuthStateManager authStateManager,
    required ProfileRepository profileRepository,
    EventBus? eventBus,
    LeaderboardRepository? fallback,
    Duration cacheTtl = const Duration(seconds: 5),
  })  : _authStateManager = authStateManager,
        _profileRepository = profileRepository,
        _fallback = fallback ?? InMemoryLeaderboardRepository(),
        _httpClient = httpClient,
        _cacheTtl = cacheTtl {
    if (eventBus != null) {
      _attemptSubscription = eventBus.on<AttemptSubmittedEvent>().listen((_) {
        _snapshotCache.clear();
        developer.log(
          'snapshot cache invalidated by AttemptSubmittedEvent',
          name: 'NetlifySupabaseLeaderboardRepository',
        );
      });
      _profileSubscription = eventBus.on<ProfileUpdatedEvent>().listen((_) {
        _snapshotCache.clear();
        developer.log(
          'snapshot cache invalidated by ProfileUpdatedEvent',
          name: 'NetlifySupabaseLeaderboardRepository',
        );
      });
      _identityResetSubscription = eventBus.on<IdentityResetEvent>().listen((_) {
        _snapshotCache.clear();
        developer.log(
          'snapshot cache invalidated by IdentityResetEvent',
          name: 'NetlifySupabaseLeaderboardRepository',
        );
      });
    }
  }

  final AuthStateManager _authStateManager;
  final ProfileRepository _profileRepository;
  final LeaderboardRepository _fallback;
  final MedRashHttpClient _httpClient;
  final Duration _cacheTtl;
  StreamSubscription<AttemptSubmittedEvent>? _attemptSubscription;
  StreamSubscription<ProfileUpdatedEvent>? _profileSubscription;
  StreamSubscription<IdentityResetEvent>? _identityResetSubscription;

  final Map<String, _CachedSnapshot> _snapshotCache = <String, _CachedSnapshot>{};

  void dispose() {
    _attemptSubscription?.cancel();
    _attemptSubscription = null;
    _profileSubscription?.cancel();
    _profileSubscription = null;
    _identityResetSubscription?.cancel();
    _identityResetSubscription = null;
  }

  Future<Map<String, Object?>?> _buildIdentityPayloadOrNull() async {
    final String? participantId = _authStateManager.participantId;
    final String? deviceInstallId = _authStateManager.deviceId;
    if (participantId == null ||
        participantId.isEmpty ||
        deviceInstallId == null ||
        deviceInstallId.isEmpty) {
      return null;
    }

    final UserProfile? profile = await _profileRepository.getProfile();
    return <String, Object?>{
      'participantId': participantId,
      'deviceInstallId': deviceInstallId,
      'profile': <String, Object?>{
        'fullName': profile?.fullName ?? 'Pilot Participant',
        'nickname': profile?.nickname ?? _guestNicknameFor(deviceInstallId),
        'facility': profile?.facility ?? 'Unknown Facility',
        'specialty': profile?.specialty ?? 'General',
      },
    };
  }

  /// Mirrors the friendly fallback used in `NetlifySupabaseQuizRepository` so
  /// nickname-less participants surface consistently across surfaces.
  String _guestNicknameFor(String deviceInstallId) {
    final String stem = deviceInstallId.length >= 4
        ? deviceInstallId.substring(0, 4)
        : deviceInstallId;
    return 'Guest-${stem.toUpperCase()}';
  }

  String _cacheKey(LeaderboardPeriod period, int limit, String? season) {
    final String type = period == LeaderboardPeriod.allTime ? 'allTime' : 'monthly';
    return '$type|${season ?? ''}|$limit';
  }

  Future<_Snapshot> _fetchSnapshot({
    required LeaderboardPeriod period,
    required int limit,
    String? season,
  }) async {
    final String key = _cacheKey(period, limit, season);
    final _CachedSnapshot? cached = _snapshotCache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.snapshot;
    }

    final Map<String, Object?> payload = <String, Object?>{
      'type': period == LeaderboardPeriod.allTime ? 'allTime' : 'monthly',
      'limit': limit,
    };
    if (period == LeaderboardPeriod.monthly && season != null && season.isNotEmpty) {
      payload['season'] = season;
    }
    final Map<String, Object?>? identity = await _buildIdentityPayloadOrNull();
    if (identity != null) {
      payload.addAll(identity);
    }

    final Map<String, dynamic> response = await _httpClient.postJson('leaderboard', payload);

    final String? seasonKey = response['seasonKey'] as String?;
    final Object? rawTop = response['top'];
    final List<LeaderboardRow> top = <LeaderboardRow>[];
    if (rawTop is List) {
      for (final Object? entry in rawTop) {
        if (entry is Map<String, dynamic>) {
          final LeaderboardRow? row = _parseRow(entry);
          if (row != null) top.add(row);
        }
      }
    }

    final Object? rawMe = response['me'];
    LeaderboardRow? me;
    if (rawMe is Map<String, dynamic>) {
      me = _parseRow(rawMe)?.copyWith(isCurrentUser: true);
    }

    final List<LeaderboardRow> mergedTop = <LeaderboardRow>[];
    final String? meUserId = me?.userId;
    for (final LeaderboardRow row in top) {
      if (meUserId != null && row.userId == meUserId) {
        mergedTop.add(row.copyWith(isCurrentUser: true));
      } else {
        mergedTop.add(row);
      }
    }

    final _Snapshot snapshot = _Snapshot(
      top: mergedTop,
      me: me,
      seasonKey: seasonKey,
    );
    _snapshotCache[key] = _CachedSnapshot(DateTime.now(), snapshot);
    return snapshot;
  }

  LeaderboardRow? _parseRow(Map<String, dynamic> row) {
    final Object? rawRank = row['rank'];
    final Object? rawScore = row['totalScore'];
    final int rank = rawRank is int ? rawRank : int.tryParse(rawRank?.toString() ?? '') ?? 0;
    final int score = rawScore is int ? rawScore : int.tryParse(rawScore?.toString() ?? '') ?? 0;
    final String name = (row['nickname'] as String? ?? '').trim();
    final String? userId = (row['userId'] as String?)?.trim();
    if (rank <= 0 || name.isEmpty) {
      return null;
    }

    final Object? rawAttempts = row['rankedAttempts'];
    final int? attempts = rawAttempts is int
        ? rawAttempts
        : int.tryParse(rawAttempts?.toString() ?? '');
    final String? rawLast = row['lastRankedAt'] as String?;
    DateTime? lastAt;
    if (rawLast != null && rawLast.isNotEmpty) {
      lastAt = DateTime.tryParse(rawLast);
    }

    return LeaderboardRow(
      rank: rank,
      name: name,
      score: score,
      userId: (userId != null && userId.isNotEmpty) ? userId : null,
      rankedAttempts: attempts,
      lastRankedAt: lastAt,
    );
  }

  @override
  Future<List<LeaderboardRow>> fetchLeaderboard({
    required LeaderboardPeriod period,
    int limit = 50,
    String? season,
  }) async {
    try {
      final _Snapshot snapshot = await _fetchSnapshot(
        period: period,
        limit: limit,
        season: season,
      );
      return snapshot.top;
    } catch (error, stack) {
      developer.log(
        'leaderboard fetch failed; using fallback',
        name: 'NetlifySupabaseLeaderboardRepository',
        error: error,
        stackTrace: stack,
      );
      return _fallback.fetchLeaderboard(
        period: period,
        limit: limit,
        season: season,
      );
    }
  }

  @override
  Future<LeaderboardRow?> fetchMyRank({
    required LeaderboardPeriod period,
    String? season,
  }) async {
    try {
      final _Snapshot snapshot = await _fetchSnapshot(
        period: period,
        limit: 1,
        season: season,
      );
      return snapshot.me;
    } catch (error, stack) {
      developer.log(
        'my-rank fetch failed; using fallback',
        name: 'NetlifySupabaseLeaderboardRepository',
        error: error,
        stackTrace: stack,
      );
      return _fallback.fetchMyRank(period: period, season: season);
    }
  }

  @override
  Future<SessionLeaderboardResult> fetchSessionLeaderboard({
    required String sessionId,
    int limit = 50,
  }) async {
    final Map<String, Object?>? identity = await _buildIdentityPayloadOrNull();
    if (identity == null) {
      // No participant identity = no way to gate membership. Fail closed
      // with the "not a participant" shape so the UI shows the play-first
      // prompt instead of leaking the board.
      return SessionLeaderboardResult(
        sessionId: sessionId,
        isLive: false,
        rows: const <SessionLeaderboardRow>[],
        requestingUserId: null,
        notAParticipant: true,
      );
    }

    final Map<String, Object?> payload = <String, Object?>{
      'sessionId': sessionId,
      'limit': limit,
      ...identity,
    };

    try {
      final Map<String, dynamic> response =
          await _httpClient.postJson('session-leaderboard', payload);
      return _parseSessionResult(sessionId: sessionId, response: response);
    } on MedRashGateException catch (error) {
      if (error.statusCode == 403 && error.code == 'NOT_SESSION_PARTICIPANT') {
        return SessionLeaderboardResult(
          sessionId: sessionId,
          isLive: _readBool(error.body['isLive']),
          rows: const <SessionLeaderboardRow>[],
          requestingUserId: null,
          endsAt: _readDateTime(error.body['endsAt']),
          closedAt: _readDateTime(error.body['closedAt']),
          notAParticipant: true,
        );
      }
      developer.log(
        'session leaderboard fetch failed',
        name: 'NetlifySupabaseLeaderboardRepository',
        error: error,
      );
      rethrow;
    }
  }

  SessionLeaderboardResult _parseSessionResult({
    required String sessionId,
    required Map<String, dynamic> response,
  }) {
    final String? requestingUserId =
        (response['requestingUserId'] as String?)?.trim();
    final List<SessionLeaderboardRow> rows = <SessionLeaderboardRow>[];
    final Object? rawTop = response['top'];
    if (rawTop is List) {
      for (final Object? entry in rawTop) {
        if (entry is Map<String, dynamic>) {
          final SessionLeaderboardRow? row = _parseSessionRow(entry);
          if (row != null) {
            final bool isMe = requestingUserId != null &&
                requestingUserId.isNotEmpty &&
                row.userId == requestingUserId;
            rows.add(isMe ? row.copyWith(isCurrentUser: true) : row);
          }
        }
      }
    }

    SessionLeaderboardRow? me;
    final Object? rawMe = response['me'];
    if (rawMe is Map<String, dynamic>) {
      me = _parseSessionRow(rawMe)?.copyWith(isCurrentUser: true);
    }

    return SessionLeaderboardResult(
      sessionId: sessionId,
      isLive: _readBool(response['isLive']),
      rows: rows,
      me: me,
      requestingUserId:
          (requestingUserId != null && requestingUserId.isNotEmpty)
              ? requestingUserId
              : null,
      endsAt: _readDateTime(response['endsAt']),
      closedAt: _readDateTime(response['closedAt']),
    );
  }

  SessionLeaderboardRow? _parseSessionRow(Map<String, dynamic> row) {
    final Object? rawRank = row['rank'];
    final int rank = rawRank is int
        ? rawRank
        : int.tryParse(rawRank?.toString() ?? '') ?? 0;
    final String userId = (row['userId'] as String? ?? '').trim();
    final String name = (row['nickname'] as String? ?? '').trim();
    if (rank <= 0 || userId.isEmpty || name.isEmpty) {
      return null;
    }

    final Object? rawScore = row['sessionScore'];
    final int score = rawScore is int
        ? rawScore
        : int.tryParse(rawScore?.toString() ?? '') ?? 0;

    final Object? rawTime = row['timeTakenMs'];
    final int timeMs = rawTime is int
        ? rawTime
        : int.tryParse(rawTime?.toString() ?? '') ?? 0;

    return SessionLeaderboardRow(
      rank: rank,
      userId: userId,
      name: name,
      sessionScore: score,
      timeTakenMs: timeMs,
      completedAt: _readDateTime(row['completedAt']),
    );
  }

  bool _readBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  DateTime? _readDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class _Snapshot {
  _Snapshot({
    required this.top,
    required this.me,
    required this.seasonKey,
  });

  final List<LeaderboardRow> top;
  final LeaderboardRow? me;
  final String? seasonKey;
}

class _CachedSnapshot {
  _CachedSnapshot(this.fetchedAt, this.snapshot);

  final DateTime fetchedAt;
  final _Snapshot snapshot;
}
