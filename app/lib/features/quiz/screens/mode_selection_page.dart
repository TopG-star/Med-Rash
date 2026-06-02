import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/motion/count_up_number.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/motion/stagger_list.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/identity_badge.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/gradient_card.dart';
import '../../../core/ui/widgets/hex_badge.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/repositories/profile_repository.dart';
import '../../profile/storage/streak_store.dart';
import '../../profile/widgets/complete_profile_banner.dart';
import '../../session/events/last_session_recorded_event.dart';
import '../../session/storage/last_session_store.dart';

/// MedRash home dashboard (Slice 2b — "Vibrant Pulse" rebuild). Three bands:
///   1. Greeting + hero featured card. The hero promotes the participant's
///      most recent open session when one is live, otherwise the daily
///      ranked challenge — both lead to a single primary CTA.
///   2. "My Stats" horizontal KPI row (streak / career points / world rank)
///      with animated count-up reveals wired to real repos.
///   3. Mode tile grid (Live / Ranked / Learn / Explore) — 2x2 on compact,
///      4-column on medium+ widths.
class ModeSelectionPage extends StatefulWidget {
  const ModeSelectionPage({super.key});

  @override
  State<ModeSelectionPage> createState() => _ModeSelectionPageState();
}

class _ModeSelectionPageState extends State<ModeSelectionPage> {
  late final LastSessionStore _lastSessionStore;
  late final StreakStore _streakStore;
  late final ProfileRepository _profileRepository;
  late final EventBus _eventBus;

  StreamSubscription<LastSessionRecordedEvent>? _lastSessionSub;
  StreamSubscription<StreakSnapshot>? _streakSub;
  StreamSubscription<ProfilePointsUpdatedEvent>? _pointsSub;
  StreamSubscription<ProfileUpdatedEvent>? _profileSub;

  LastSessionRecord? _lastSession;
  StreakSnapshot _streak = StreakSnapshot.empty;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _lastSessionStore = getIt<LastSessionStore>();
    _streakStore = getIt<StreakStore>();
    _profileRepository = getIt<ProfileRepository>();
    _eventBus = getIt<EventBus>();

    _lastSession = _lastSessionStore.read();
    _streak = _streakStore.read();
    _loadProfile();

    _lastSessionSub = _eventBus
        .on<LastSessionRecordedEvent>()
        .listen((_) => _refreshLastSession());
    _streakSub = _streakStore.changes.listen((StreakSnapshot snap) {
      if (mounted) setState(() => _streak = snap);
    });
    _pointsSub = _eventBus
        .on<ProfilePointsUpdatedEvent>()
        .listen((_) => _loadProfile());
    _profileSub = _eventBus
        .on<ProfileUpdatedEvent>()
        .listen((_) => _loadProfile());
  }

  @override
  void dispose() {
    _lastSessionSub?.cancel();
    _streakSub?.cancel();
    _pointsSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final UserProfile? loaded = await _profileRepository.getProfile();
    if (!mounted) return;
    setState(() => _profile = loaded);
  }

  void _refreshLastSession() {
    if (!mounted) return;
    setState(() => _lastSession = _lastSessionStore.read());
  }

  void _go(String path) {
    Haptics.selection();
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String? handle = _profile != null && _profile!.nickname.isNotEmpty
        ? '@${_profile!.nickname}'
        : null;
    final String greeting =
        handle != null ? 'Hello, $handle' : MedRashStrings.homeGreetingFallback;

    return ArenaScaffold(
      title: MedRashStrings.appTitle,
      bottomNav: true,
      actions: const <Widget>[IdentityBadge()],
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const CompleteProfileBanner(),
          _Greeting(greeting: greeting),
          const SizedBox(height: MedRashSpace.lg),
          _HeroFeaturedCard(
            lastSession: _lastSession,
            onResume: (String joinCode) =>
                _go('/session/${Uri.encodeComponent(joinCode)}'),
            onRanked: () => _go('/ranked'),
          ),
          const SizedBox(height: MedRashSpace.xl),
          _StatsHeading(
            title: MedRashStrings.homeStatsHeading,
            actionLabel: MedRashStrings.homeStatsViewAll,
            onActionTap: () => _go('/profile'),
          ),
          const SizedBox(height: MedRashSpace.sm),
          _StatsRow(
            streak: _streak.currentStreak,
            careerPoints: _profile?.totalPoints ?? 0,
            worldRank: _profile?.rank ?? 0,
          ),
          const SizedBox(height: MedRashSpace.xl),
          Text(
            MedRashStrings.homeModesHeading,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
          ),
          const SizedBox(height: MedRashSpace.sm),
          _ModeGrid(
            tiles: <_ModeTileData>[
              _ModeTileData(
                label: MedRashStrings.modeLiveLabel,
                description: MedRashStrings.modeLiveDescription,
                icon: Icons.podcasts_rounded,
                accent: tokens.primary,
                accentSoft: tokens.primarySoft,
                surfaceColor: tokens.cardLavender,
                onTap: () => _go('/live'),
              ),
              _ModeTileData(
                label: MedRashStrings.modeRankedLabel,
                description: MedRashStrings.modeRankedDescription,
                icon: Icons.workspace_premium_rounded,
                accent: tokens.onSecondary,
                accentSoft: tokens.secondary,
                surfaceColor: tokens.cardGold,
                onTap: () => _go('/ranked'),
              ),
              _ModeTileData(
                label: MedRashStrings.modeLearnLabel,
                description: MedRashStrings.modeLearnDescription,
                icon: Icons.menu_book_rounded,
                accent: tokens.primaryStrong,
                accentSoft: tokens.primarySoft,
                surfaceColor: tokens.cardMint,
                onTap: () => _go('/learn'),
              ),
              _ModeTileData(
                label: MedRashStrings.exploreTitle,
                description: MedRashStrings.exploreIntro,
                icon: Icons.travel_explore_rounded,
                accent: tokens.primary,
                accentSoft: tokens.primarySoft,
                surfaceColor: tokens.cardPeach,
                onTap: () => _go('/explore'),
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.lg),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.greeting});

  final String greeting;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          greeting,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: MedRashSpace.xs),
        Text(
          MedRashStrings.homeGreetingTagline,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _HeroFeaturedCard extends StatelessWidget {
  const _HeroFeaturedCard({
    required this.lastSession,
    required this.onResume,
    required this.onRanked,
  });

  final LastSessionRecord? lastSession;
  final void Function(String joinCode) onResume;
  final VoidCallback onRanked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool isResume = lastSession != null;
    final String tag = isResume
        ? MedRashStrings.homeFeaturedTagSession
        : MedRashStrings.homeFeaturedTagRanked;
    final String title = isResume
        ? 'Session ${lastSession!.joinCode}'
        : MedRashStrings.homeFeaturedTitleRanked;
    final String body = isResume
        ? 'You opened this session ${_formatAgo(DateTime.now().difference(lastSession!.openedAt))}. Jump back in before the cohort moves on.'
        : MedRashStrings.homeFeaturedBodyRanked;
    final String cta = isResume
        ? MedRashStrings.homeFeaturedCtaResume
        : MedRashStrings.homeFeaturedCtaRanked;
    final VoidCallback onPressed =
        isResume ? () => onResume(lastSession!.joinCode) : onRanked;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusLarge + 4),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.primary.withValues(alpha: 0.22),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ),
        GradientCard(
          gradient: MedRashGradient.primaryHeader(tokens),
          padding: const EdgeInsets.all(MedRashSpace.lg),
          borderColor: Colors.white.withValues(alpha: 0.18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tag.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                ),
              ),
              const SizedBox(height: MedRashSpace.md),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: MedRashSpace.xs),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
              ),
              const SizedBox(height: MedRashSpace.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: PressScale(
                  onTap: () {
                    Haptics.submit();
                    onPressed();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(tokens.radiusMedium),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          cta,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                color: tokens.primaryStrong,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.play_arrow_rounded,
                          size: MedRashIconSize.md,
                          color: tokens.primaryStrong,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatAgo(Duration diff) {
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      final int m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    final int h = diff.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
}

class _StatsHeading extends StatelessWidget {
  const _StatsHeading({
    required this.title,
    required this.actionLabel,
    required this.onActionTap,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onActionTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
        ),
        TextButton(
          onPressed: onActionTap,
          child: Text(
            actionLabel,
            style: TextStyle(
              color: tokens.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.streak,
    required this.careerPoints,
    required this.worldRank,
  });

  final int streak;
  final int careerPoints;
  final int worldRank;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          _StatTile(
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFEA580C),
            iconBackground: const Color(0xFFFFE9D6),
            surfaceColor: tokens.cardGold,
            value: streak,
            label: MedRashStrings.homeStatStreak,
          ),
          const SizedBox(width: MedRashSpace.md),
          _StatTile(
            icon: Icons.military_tech_rounded,
            iconColor: tokens.primary,
            iconBackground: tokens.primarySoft,
            surfaceColor: tokens.cardLavender,
            value: careerPoints,
            label: MedRashStrings.homeStatPoints,
          ),
          const SizedBox(width: MedRashSpace.md),
          _StatTile(
            icon: Icons.leaderboard_rounded,
            iconColor: tokens.onSecondary,
            iconBackground: tokens.secondary,
            surfaceColor: tokens.cardPeach,
            value: worldRank,
            label: MedRashStrings.homeStatRank,
            prefix: worldRank > 0 ? '#' : null,
            zeroPlaceholder: '\u2014',
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.surfaceColor,
    required this.value,
    required this.label,
    this.prefix,
    this.zeroPlaceholder,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Color surfaceColor;
  final int value;
  final String label;
  final String? prefix;
  final String? zeroPlaceholder;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final TextStyle? displayStyle =
        Theme.of(context).textTheme.displaySmall?.copyWith(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
              height: 1,
            );
    return SizedBox(
      width: 168,
      child: GradientCard(
        color: surfaceColor,
        padding: const EdgeInsets.all(MedRashSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            HexBadge(
              size: 48,
              fillColor: iconBackground,
              borderColor: iconColor,
              child: Icon(icon, color: iconColor, size: MedRashIconSize.lg),
            ),
            const SizedBox(height: MedRashSpace.sm),
            if (zeroPlaceholder != null && value == 0)
              Text(zeroPlaceholder!, style: displayStyle)
            else
              CountUpNumber(
                value: value,
                style: displayStyle,
                formatter: (int v) => '${prefix ?? ''}$v',
              ),
            const SizedBox(height: MedRashSpace.xs),
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTileData {
  const _ModeTileData({
    required this.label,
    required this.description,
    required this.icon,
    required this.accent,
    required this.accentSoft,
    required this.surfaceColor,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color accent;
  final Color accentSoft;
  final Color surfaceColor;
  final VoidCallback onTap;
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.tiles});

  final List<_ModeTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int cols = constraints.maxWidth >= 600 ? 4 : 2;
        return StaggerList(
          children: <Widget>[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tiles.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: MedRashSpace.md,
                crossAxisSpacing: MedRashSpace.md,
                childAspectRatio: cols == 2 ? 1.05 : 0.95,
              ),
              itemBuilder: (BuildContext context, int i) =>
                  _ModeTile(data: tiles[i]),
            ),
          ],
        );
      },
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.data});

  final _ModeTileData data;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return PressScale(
      onTap: data.onTap,
      child: GradientCard(
        color: data.surfaceColor,
        padding: const EdgeInsets.all(MedRashSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            HexBadge(
              size: 44,
              fillColor: data.accentSoft,
              borderColor: data.accent,
              child: Icon(
                data.icon,
                color: data.accent,
                size: MedRashIconSize.lg,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  data.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.3,
                      ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
