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
import '../../../core/ui/widgets/hex_badge.dart';
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
                    if (currentUser != null &&
                        currentUser.rank > 1 &&
                        rows.length >= 5) ...<Widget>[
                      const SizedBox(height: MedRashSpace.lg),
                      _PersonalRankBanner(
                        rank: currentUser.rank,
                        totalPlayers: rows.length,
                      ),
                    ],
                    if (!_allTime) ...<Widget>[
                      const SizedBox(height: MedRashSpace.md),
                      const _SeasonCountdown(),
                    ],
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
                    medalColor: null, // set inside slot from tokens
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
                    medalColor: null,
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
    this.medalColor,
  });

  final LeaderboardRow row;
  final int rank;
  final PodiumTier tier;
  final double blockHeight;
  final bool champion;

  /// P8.a — optional override for the small medal icon rendered above
  /// non-champion avatars. When null the slot resolves silver for rank 2
  /// and bronze for rank 3 from `ArenaDesignTokens`; ignored for the
  /// champion (which uses its own gold workspace-premium glyph).
  final Color? medalColor;

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
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      size: 18,
                      color: medalColor ??
                          (rank == 2 ? tokens.rankSilver : tokens.rankBronze),
                    ),
                  ),
                GamifiedAvatar(
                  spec: () {
                    final String? s = row.seed ?? row.userId;
                    return (s != null && s.isNotEmpty)
                        ? NaviiAvatarSpec(
                            seed: s,
                            fallbackSource: row.name,
                            fallbackTint:
                                row.isCurrentUser ? tokens.primary : null,
                          )
                        : MonogramAvatarSpec(
                            source: row.name,
                            tint: row.isCurrentUser ? tokens.primary : null,
                          );
                  }(),
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
              spec: () {
                final String? s = row.seed ?? row.userId;
                return (s != null && s.isNotEmpty)
                    ? NaviiAvatarSpec(
                        seed: s,
                        fallbackSource: row.name,
                        fallbackTint: you ? tokens.primary : tokens.secondary,
                      )
                    : MonogramAvatarSpec(
                        source: row.name,
                        tint: you ? tokens.primary : tokens.secondary,
                      );
              }(),
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
            if (row.rank >= 1 && row.rank <= 3) ...<Widget>[
              const SizedBox(width: MedRashSpace.sm),
              _RankMedal(rank: row.rank),
            ],
          ],
        ),
      ),
    );
  }
}

/// P9.c -- top-3 trailing hex medal used inside the scrollable leader
/// list (the podium already has its own larger crown / medal glyphs).
/// Gold/silver/bronze hex with a small crown icon, matching the
/// reference leaderboard list rows.
class _RankMedal extends StatelessWidget {
  const _RankMedal({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color metal;
    switch (rank) {
      case 1:
        metal = tokens.rankGold;
        break;
      case 2:
        metal = tokens.rankSilver;
        break;
      case 3:
      default:
        metal = tokens.rankBronze;
        break;
    }
    return HexBadge(
      size: 32,
      fillColor: metal,
      borderColor: metal,
      child: const Icon(
        Icons.workspace_premium_rounded,
        color: Colors.white,
        size: 18,
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
                spec: () {
                  final String? s = row.seed ?? row.userId;
                  return (s != null && s.isNotEmpty)
                      ? NaviiAvatarSpec(
                          seed: s,
                          fallbackSource: row.name,
                          fallbackTint: tokens.secondary,
                        )
                      : MonogramAvatarSpec(
                          source: row.name,
                          tint: tokens.secondary,
                        );
                }(),
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

/// P8.a — peach personal-rank banner sourced from the reference podium
/// screen. Surfaces "#N you are doing better than X% of other players"
/// above the period toggle so a participant always knows their relative
/// standing without scrolling through the contender list to find their
/// row. Hidden when the participant is #1 or the sample is too small
/// (<5 ranked players) for the percentile to mean anything.
class _PersonalRankBanner extends StatelessWidget {
  const _PersonalRankBanner({
    required this.rank,
    required this.totalPlayers,
  });

  final int rank;
  final int totalPlayers;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    // Percentile = share of players the current user is ahead of.
    final int percentile = totalPlayers <= 1
        ? 0
        : (((totalPlayers - rank) / (totalPlayers - 1)) * 100).round();
    return Semantics(
      container: true,
      label:
          'Rank $rank, you are doing better than $percentile percent of other players',
      child: ArenaCard(
        color: tokens.warningSurface,
        padding: const EdgeInsets.symmetric(
          horizontal: MedRashSpace.md,
          vertical: MedRashSpace.md,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.secondaryStrong,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
              ),
              child: Text(
                '#$rank',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
              ),
            ),
            const SizedBox(width: MedRashSpace.md),
            Expanded(
              child: Text(
                'You are doing better than $percentile% of other players!',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: tokens.onSecondary,
                      height: 1.3,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// P8.a — countdown chip rendered only on the Monthly board. The world
/// rank for All-Time has no expiry so the chip is hidden there. Self
/// re-renders every minute via an internal Timer so the parent stays
/// stateless w.r.t. clock ticks. Format: `Dd HHh MMm` (mirrors the
/// Stitch reference "06d 23h 00m").
class _SeasonCountdown extends StatefulWidget {
  const _SeasonCountdown();

  @override
  State<_SeasonCountdown> createState() => _SeasonCountdownState();
}

class _SeasonCountdownState extends State<_SeasonCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _untilEndOfMonth() {
    final DateTime now = DateTime.now();
    // Last instant of the current month — the first day of next month
    // minus one second. UTC drift is acceptable for a display-only chip.
    final DateTime firstOfNextMonth = (now.month == 12)
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    return firstOfNextMonth.subtract(const Duration(seconds: 1)).difference(now);
  }

  String _format(Duration d) {
    final int days = d.inDays;
    final int hours = d.inHours.remainder(24);
    final int minutes = d.inMinutes.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(days)}d ${two(hours)}h ${two(minutes)}m';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String text = _format(_untilEndOfMonth());
    return Center(
      child: Semantics(
        container: true,
        label: 'Monthly season ends in $text',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MedRashSpace.md,
            vertical: MedRashSpace.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.outlineMuted, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.schedule_rounded,
                size: 16,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                      letterSpacing: 0.4,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
