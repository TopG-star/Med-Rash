import 'dart:async';

import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/medrash_http_client.dart';
import '../models/participant_stats.dart';
import '../models/user_profile.dart';
import 'profile_repository.dart';

/// P8.c — repository that pulls participant-side analytics from the
/// `participant-stats` Netlify function. Returns
/// [ParticipantStats.empty] when the participant has no identity yet so
/// the Stats tab can render a non-blocking empty state instead of
/// surfacing a network error to a brand-new device.
class ParticipantStatsRepository {
  ParticipantStatsRepository({
    required MedRashHttpClient httpClient,
    required AuthStateManager authStateManager,
    required ProfileRepository profileRepository,
  })  : _httpClient = httpClient,
        _authStateManager = authStateManager,
        _profileRepository = profileRepository;

  final MedRashHttpClient _httpClient;
  final AuthStateManager _authStateManager;
  final ProfileRepository _profileRepository;

  Future<ParticipantStats> fetchMonthly() async {
    final String? participantId = _authStateManager.participantId;
    final String? deviceInstallId = _authStateManager.deviceId;
    if (participantId == null ||
        participantId.isEmpty ||
        deviceInstallId == null ||
        deviceInstallId.isEmpty) {
      return ParticipantStats.empty;
    }

    final UserProfile? profile = await _profileRepository.getProfile();
    final Map<String, Object?> payload = <String, Object?>{
      'participantId': participantId,
      'deviceInstallId': deviceInstallId,
      'period': 'monthly',
      'profile': <String, Object?>{
        'fullName': profile?.fullName ?? 'Pilot Participant',
        'nickname': profile?.nickname ?? 'guest',
        'facility': profile?.facility ?? 'Unknown Facility',
        'specialty': profile?.specialty ?? 'General',
      },
    };

    final Map<String, dynamic> body =
        await _httpClient.postJson('participant-stats', payload);

    if (body['ok'] != true) {
      // Surface as empty rather than throwing — the Stats tab degrades
      // gracefully to the "no attempts yet" state. Network/gate errors
      // are already logged by MedRashHttpClient.
      return ParticipantStats.empty;
    }
    return ParticipantStats.fromJson(body);
  }
}
