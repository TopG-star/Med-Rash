import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/profile/models/user_profile.dart';
import '../../features/profile/repositories/profile_repository.dart';
import '../di/get_it.dart';
import '../events/medrash_events.dart';
import '../infra/event_bus.dart';
import '../theme/theme_extensions.dart';

/// Compact identity chip rendered in the top-right of the home, leaderboard,
/// and result scaffolds. Shows `@nickname · facility` so the participant can
/// confirm at a glance which leaderboard row their next attempt will hit.
class IdentityBadge extends StatefulWidget {
  const IdentityBadge({super.key});

  @override
  State<IdentityBadge> createState() => _IdentityBadgeState();
}

class _IdentityBadgeState extends State<IdentityBadge> {
  late final ProfileRepository _profileRepository;
  late final EventBus _eventBus;
  StreamSubscription<ProfileUpdatedEvent>? _profileSubscription;
  StreamSubscription<IdentityResetEvent>? _identitySubscription;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _profileRepository = getIt<ProfileRepository>();
    _eventBus = getIt<EventBus>();
    _load();
    _profileSubscription = _eventBus.on<ProfileUpdatedEvent>().listen((_) => _load());
    _identitySubscription = _eventBus.on<IdentityResetEvent>().listen((_) => _load());
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _identitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final UserProfile? profile = await _profileRepository.getProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
    });
  }

  @override
  Widget build(BuildContext context) {
    final UserProfile? profile = _profile;
    if (profile == null) {
      return const SizedBox.shrink();
    }

    final tokens = context.arenaTokens;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: Semantics(
          label: 'Signed in as @${profile.nickname} from ${profile.facility}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
              border: Border.all(color: tokens.outline, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.person_rounded, size: 16, color: tokens.outline),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    '@${profile.nickname}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
