import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../storage/guest_profile_prompt_store.dart';

/// Soft nudge for guests who've played at least one round on this device:
/// "Complete your profile so your scores follow you across devices."
///
/// Rendered above the main scroll content on Home (mode selection) and the
/// Ranked Mode page. Dismissible — once dismissed it does not return on
/// either surface until the participant either signs out or graduates to a
/// real nickname (both events wipe [GuestProfilePromptStore]).
class CompleteProfileBanner extends StatefulWidget {
  const CompleteProfileBanner({super.key});

  @override
  State<CompleteProfileBanner> createState() => _CompleteProfileBannerState();
}

class _CompleteProfileBannerState extends State<CompleteProfileBanner> {
  late final ProfileRepository _profileRepository;
  late final GuestProfilePromptStore _promptStore;
  late final EventBus _eventBus;
  StreamSubscription<ProfileUpdatedEvent>? _profileSub;
  StreamSubscription<IdentityResetEvent>? _identitySub;
  UserProfile? _profile;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _profileRepository = getIt<ProfileRepository>();
    _promptStore = getIt<GuestProfilePromptStore>();
    _eventBus = getIt<EventBus>();
    _promptStore.addListener(_onStoreChanged);
    _profileSub = _eventBus.on<ProfileUpdatedEvent>().listen((_) => _loadProfile());
    _identitySub = _eventBus.on<IdentityResetEvent>().listen((_) => _loadProfile());
    _loadProfile();
  }

  @override
  void dispose() {
    _promptStore.removeListener(_onStoreChanged);
    _profileSub?.cancel();
    _identitySub?.cancel();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    final UserProfile? profile = await _profileRepository.getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (!_promptStore.shouldShow(_profile)) return const SizedBox.shrink();

    final tokens = context.arenaTokens;
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: ArenaCard(
        color: tokens.warningSurface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.account_circle_outlined, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Complete your profile',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add your full name and facility so your ranked scores '
                    'follow you across devices.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Complete profile'),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close),
              onPressed: () => _promptStore.dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
