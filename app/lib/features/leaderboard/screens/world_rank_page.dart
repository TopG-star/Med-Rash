import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/motion/count_up_number.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/stagger_list.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/identity_badge.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/empty_state.dart';
import '../../../core/ui/widgets/gamified_avatar.dart';
import '../../../core/ui/widgets/pill_segmented_control.dart';
import '../../../core/ui/widgets/podium_block.dart';
import '../../profile/models/avatar_spec.dart';
import '../models/leaderboard_row.dart';
import '../repositories/leaderboard_repository.dart';

class WorldRankPage extends StatefulWidget {
  const WorldRankPage({super.key});

  @override
  State<WorldRankPage> createState() => _WorldRankPageState();
}

class _WorldRankPageState extends State<WorldRankPage> {
  bool _allTime = true;
  late final LeaderboardRepository _leaderboardRepository;
  StreamSubscription<AttemptSubmittedEvent>? _attemptSubscription;
  Future<List<LeaderboardRow>>? _futureRows;

  @override
  void initState() {
    super.initState();
    _leaderboardRepository = getIt<LeaderboardRepository>();
    _futureRows = _leaderboardRepository.fetchLeaderboard(
      period: LeaderboardPeriod.allTime,
    );
    _attemptSubscription =
        getIt<EventBus>().on<AttemptSubmittedEvent>().listen((_) {
      if (!mounted) return;
      setState(() {
        _futureRows = _leaderboardRepository.fetchLeaderboard(
          period:
              _allTime ? LeaderboardPeriod.allTime : LeaderboardPeriod.monthly,
        );
      });
    });
  }

  @override
  void dispose() {
    _attemptSubscription?.cancel();
    super.dispose();
  }

  Future<void> _switchPeriod(bool allTime) async {
    if (allTime == _allTime) return;
    Haptics.selection();
    setState(() {
      _allTime = allTime;
      _futureRows = _leaderboardRepository.fetchLeaderboard(
        period:
            allTime ? LeaderboardPeriod.allTime : LeaderboardPeriod.monthly,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: MedRashStrings.leaderboardTitle,
      showBack: true,
      bottomNav: true,
      actions: const <Widget>[IdentityBadge()],
      child: FutureBuilder<List<LeaderboardRow>>(
        future: _futureRows,
        builder: (BuildContext context,
            AsyncSnapshot<List<LeaderboardRow>> snapshot) {
          if (!snapshot.hasData) {
            return const MedRashConstrainedBody(
              child: MedRashSkeletonList(),
            );
          }

          final List<LeaderboardRow> rows = snapshot.data!;
          final List<LeaderboardRow> podium = rows.take(3).toList();
          final List<LeaderboardRow> rest = rows.skip(3).toList();
          LeaderboardRow? currentUser;
          for (final LeaderboardRow row in rows) {
            if (row.isCurrentUser) {
              currentUser = row;
              break;
            }
          }
          final bool currentInPodium = currentUser != null &&
              podium.any((LeaderboardRow r) => r.isCurrentUser);

          return MedRashConstrainedBody(
            child: Stack(
              children: <Widget>[
                ListView(
                  padding: EdgeInsets.only(
                    bottom: currentUser != null && !currentInPodium
                        ? 96
                        : MedRashSpace.lg,
                  ),
                  children: <Widget>[
                    _PeriodToggle(
                      allTime: _allTime,
                      onSelect: _switchPeriod,
                    ),
                    const SizedBox(height: MedRashSpace.xl),
                    if (podium.isNotEmpty)
                      _Podium(podium: podium)
                    else
                      const _EmptyState(),
                    if (rest.isNotEmpty) ...<Widget>[
                      const SizedBox(height: MedRashSpace.xl),
                      Padding(
                        padding: const EdgeInsets.only(
                          left: MedRashSpace.xs,
                          bottom: MedRashSpace.sm,
                        ),
                        child: Text(
                          'CONTENDERS',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w800,
                                color: context.arenaTokens.textSecondary,
                                letterSpacing: 1.0,
                              ),
                        ),
                      ),
                      StaggerList(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        itemDuration: const Duration(milliseconds: 360),
                        itemDelay: const Duration(milliseconds: 50),
                        children: <Widget>[
                          for (final LeaderboardRow row in rest)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: MedRashSpace.md,
                              ),
                              child: _LeaderRow(row: row),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (currentUser != null && !currentInPodium)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MedRashSpace.md,
                    child: _StickyYouCard(row: currentUser),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.allTime, required this.onSelect});

  final bool allTime;
  final Future<void> Function(bool allTime) onSelect;

  @override
  Widget build(BuildContext context) {
    return PillSegmentedControl<bool>(
      segments: const <PillSegment<bool>>[
        PillSegment<bool>(
          value: false,
          label: MedRashStrings.leaderboardMonthly,
        ),
        PillSegment<bool>(
          value: true,
          label: MedRashStrings.leaderboardAllTime,
        ),
      ],
      value: allTime,
      onChanged: (bool v) => onSelect(v),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.podium});

  final List<LeaderboardRow> podium;

  // Riser heights (per reference UI 5): #1 tallest in the middle, #2 left,
  // #3 right. Avatars float above the risers and visually overlap the top
  // edge by half their diameter via Stack.
  static const double _firstHeight = 180;
  static const double _secondHeight = 140;
  static const double _thirdHeight = 110;
  static const double _avatarDiameter = 72;
  static const double _avatarOverlap = 28;

  @override
  Widget build(BuildContext context) {
    final LeaderboardRow? first = podium.isNotEmpty ? podium[0] : null;
    final LeaderboardRow? second = podium.length >= 2 ? podium[1] : null;
    final LeaderboardRow? third = podium.length >= 3 ? podium[2] : null;
    return SizedBox(
      height: _firstHeight + _avatarDiameter + 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: second != null
                ? _PodiumSlot(
                    row: second,
                    rank: 2,
                    tier: PodiumTier.silver,
                    blockHeight: _secondHeight,
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: MedRashSpace.md),
          Expanded(
            child: first != null
                ? _PodiumSlot(
                    row: first,
                    rank: 1,
                    tier: PodiumTier.gold,
                    blockHeight: _firstHeight,
                    champion: true,
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: MedRashSpace.md),
          Expanded(
            child: third != null
                ? _PodiumSlot(
                    row: third,
                    rank: 3,
                    tier: PodiumTier.bronze,
                    blockHeight: _thirdHeight,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.row,
    required this.rank,
    required this.tier,
    required this.blockHeight,
    this.champion = false,
  });

  final LeaderboardRow row;
  final int rank;
  final PodiumTier tier;
  final double blockHeight;
  final bool champion;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    // Avatar ring gradient: champion gets the gold podium gradient as a
    // crown-like halo; others get a tier-tinted solid "gradient".
    final Gradient ringGradient = champion
        ? MedRashGradient.podiumGold(tokens)
        : LinearGradient(
            colors: <Color>[tokens.primary, tokens.primary],
          );

    return Semantics(
      container: true,
      label: row.isCurrentUser
          ? 'Rank $rank, you, ${row.name}'
          : 'Rank $rank, ${row.name}',
      value: '${row.score} points',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          // The riser — tier-gradient block with rank numeral on the face.
          PodiumBlock(
            tier: tier,
            height: blockHeight,
            rankNumeral: rank,
            label: _formatScore(row.score, row.name),
          ),
          // Avatar floats above the riser, overlapping the top edge.
          Positioned(
            bottom: blockHeight - _Podium._avatarOverlap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (champion)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      size: 22,
                      color: tokens.rankGold,
                    ),
                  ),
                GamifiedAvatar(
                  spec: MonogramAvatarSpec(
                    source: row.name,
                    tint: row.isCurrentUser ? tokens.primary : null,
                  ),
                  diameter: _Podium._avatarDiameter,
                  ringWidth: champion ? 3 : 2,
                  ringGradient: ringGradient,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Compose the riser label: "NAME • {score} pts" — kept compact so it
  // fits the 96 dp riser width without ellipsis on common nicknames.
  String _formatScore(int score, String name) {
    final String trimmedName = name.length > 10
        ? '${name.substring(0, 9)}\u2026'
        : name;
    return '$trimmedName\n$score pts';
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.row});

  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool you = row.isCurrentUser;
    return Semantics(
      container: true,
      label: you ? 'Rank ${row.rank}, you, ${row.name}' : 'Rank ${row.rank}, ${row.name}',
      value: '${row.score} points',
      child: ArenaCard(
        color: you ? tokens.primarySoft : tokens.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: MedRashSpace.md,
          vertical: MedRashSpace.md,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: you ? tokens.primary : tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
              ),
              child: Text(
                '#${row.rank}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: you ? Colors.white : tokens.primaryStrong,
                      letterSpacing: 0.4,
                    ),
              ),
            ),
            const SizedBox(width: MedRashSpace.md),
            GamifiedAvatar(
              spec: MonogramAvatarSpec(
                source: row.name,
                tint: you ? tokens.primary : tokens.secondary,
              ),
              diameter: 44,
              ringWidth: 2,
              ringGradient: LinearGradient(
                colors: <Color>[
                  you ? tokens.primary : tokens.outline,
                  you ? tokens.primary : tokens.outline,
                ],
              ),
            ),
            const SizedBox(width: MedRashSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: you ? tokens.primaryStrong : tokens.textPrimary,
                        ),
                  ),
                  if (you)
                    Text(
                      'YOU',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: tokens.primaryStrong,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: MedRashSpace.sm),
            CountUpNumber(
              value: row.score,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    color: you ? tokens.primaryStrong : tokens.textPrimary,
                  ),
            ),
            const SizedBox(width: 4),
            Text(
              'pts',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyYouCard extends StatelessWidget {
  const _StickyYouCard({required this.row});

  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MedRashSpace.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: tokens.primary.withValues(alpha: 0.28),
              blurRadius: 22,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ArenaCard(
          color: tokens.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: MedRashSpace.md,
            vertical: MedRashSpace.md,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.secondary,
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                ),
                child: Text(
                  '#${row.rank}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        color: tokens.onSecondary,
                        letterSpacing: 0.4,
                      ),
                ),
              ),
              const SizedBox(width: MedRashSpace.md),
              GamifiedAvatar(
                spec: MonogramAvatarSpec(
                  source: row.name,
                  tint: tokens.secondary,
                ),
                diameter: 44,
                ringWidth: 2,
                ringGradient: const LinearGradient(
                  colors: <Color>[Colors.white, Colors.white],
                ),
              ),
              const SizedBox(width: MedRashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'YOU',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                    ),
                    Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MedRashSpace.sm),
              CountUpNumber(
                value: row.score,
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(width: 4),
              Text(
                'pts',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const MedRashEmptyState(
      icon: Icons.emoji_events_rounded,
      title: 'Be the first on the podium',
      body:
          'No ranked attempts have synced for this pilot yet. Finish a ranked attempt to claim the inaugural top spot.',
    );
  }
}
