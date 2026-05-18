import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/infra/auth_state_manager.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/repositories/profile_repository.dart';
import '../models/leaderboard_row.dart';
import 'leaderboard_repository.dart';

class NetlifySupabaseLeaderboardRepository implements LeaderboardRepository {
  NetlifySupabaseLeaderboardRepository({
    required String functionsBaseUrl,
    required AuthStateManager authStateManager,
    required ProfileRepository profileRepository,
    LeaderboardRepository? fallback,
    http.Client? httpClient,
    String? gateApiKey,
    Duration cacheTtl = const Duration(seconds: 5),
  })  : _authStateManager = authStateManager,
        _profileRepository = profileRepository,
        _fallback = fallback ?? InMemoryLeaderboardRepository(),
        _httpClient = httpClient ?? http.Client(),
        _gateApiKey = gateApiKey,
        _cacheTtl = cacheTtl,
        _baseFunctionsUri = _normalizeFunctionsUri(functionsBaseUrl);

  final AuthStateManager _authStateManager;
  final ProfileRepository _profileRepository;
  final LeaderboardRepository _fallback;
  final http.Client _httpClient;
  final String? _gateApiKey;
  final Duration _cacheTtl;
  final Uri _baseFunctionsUri;

  final Map<String, _CachedSnapshot> _snapshotCache = <String, _CachedSnapshot>{};

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
        'nickname': profile?.nickname ?? 'PilotUser',
        'facility': profile?.facility ?? 'Unknown Facility',
        'specialty': profile?.specialty ?? 'General',
      },
    };
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

    final Map<String, dynamic> response = await _postJson('leaderboard', payload);

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
    } catch (_) {
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
    } catch (_) {
      return _fallback.fetchMyRank(period: period, season: season);
    }
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

class _GateHttpException implements Exception {
  _GateHttpException({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;
}
