import 'dart:async';

import 'package:flutter/material.dart';

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
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/empty_state.dart';
import '../../../core/ui/widgets/monogram_avatar.dart';
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
    final tokens = context.arenaTokens;
    return Container(
      padding: const EdgeInsets.all(MedRashSpace.xs + 2),
      decoration: BoxDecoration(
        color: tokens.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SegmentPill(
              label: MedRashStrings.leaderboardMonthly,
              selected: !allTime,
              onTap: () => onSelect(false),
            ),
          ),
          Expanded(
            child: _SegmentPill(
              label: MedRashStrings.leaderboardAllTime,
              selected: allTime,
              onTap: () => onSelect(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool reducedMotion = MediaQuery.of(context).disableAnimations;
    return PressScale(
      enabled: !selected,
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: MedRashSpace.sm + 2),
        decoration: BoxDecoration(
          color: selected ? tokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: tokens.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : tokens.primaryStrong,
                letterSpacing: 0.4,
              ),
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.podium});

  final List<LeaderboardRow> podium;

  @override
  Widget build(BuildContext context) {
    final LeaderboardRow? first = podium.isNotEmpty ? podium[0] : null;
    final LeaderboardRow? second = podium.length >= 2 ? podium[1] : null;
    final LeaderboardRow? third = podium.length >= 3 ? podium[2] : null;
    final tokens = context.arenaTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: second != null
              ? _PodiumColumn(
                  row: second,
                  rank: 2,
                  surface: tokens.primarySoft,
                  accent: tokens.primary,
                  height: 200,
                  avatarBg: tokens.primary,
                  avatarFg: Colors.white,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: MedRashSpace.md),
        Expanded(
          child: first != null
              ? _PodiumColumn(
                  row: first,
                  rank: 1,
                  surface: tokens.secondary,
                  accent: tokens.onSecondary,
                  height: 240,
                  champion: true,
                  avatarBg: tokens.onSecondary,
                  avatarFg: tokens.secondary,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: MedRashSpace.md),
        Expanded(
          child: third != null
              ? _PodiumColumn(
                  row: third,
                  rank: 3,
                  surface: tokens.tertiary,
                  accent: Colors.white,
                  height: 200,
                  avatarBg: Colors.white,
                  avatarFg: tokens.tertiary,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.row,
    required this.rank,
    required this.surface,
    required this.accent,
    required this.height,
    required this.avatarBg,
    required this.avatarFg,
    this.champion = false,
  });

  final LeaderboardRow row;
  final int rank;
  final Color surface;
  final Color accent;
  final double height;
  final bool champion;
  final Color avatarBg;
  final Color avatarFg;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Semantics(
      container: true,
      label: row.isCurrentUser
          ? 'Rank $rank, you, ${row.name}'
          : 'Rank $rank, ${row.name}',
      value: '${row.score} points',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: ArenaCard(
              color: surface,
              padding: const EdgeInsets.fromLTRB(
                MedRashSpace.sm,
                MedRashSpace.xxl,
                MedRashSpace.sm,
                MedRashSpace.lg,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MedRashSpace.sm + 2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#$rank',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: 0.4,
                          ),
                    ),
                  ),
                  const SizedBox(height: MedRashSpace.sm),
                  Text(
                    row.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                  ),
                  const SizedBox(height: MedRashSpace.sm),
                  CountUpNumber(
                    value: row.score,
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          color: accent,
                          height: 1,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'pts',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: accent.withValues(alpha: 0.75),
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -28,
            child: _PodiumAvatar(
              source: row.name,
              avatarBg: avatarBg,
              avatarFg: avatarFg,
              champion: champion,
              ringColor: champion ? tokens.secondary : surface,
            ),
          ),
          if (champion)
            Positioned(
              top: -54,
              child: Icon(
                Icons.workspace_premium_rounded,
                color: tokens.secondary,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }
}

class _PodiumAvatar extends StatelessWidget {
  const _PodiumAvatar({
    required this.source,
    required this.avatarBg,
    required this.avatarFg,
    required this.ringColor,
    required this.champion,
  });

  final String source;
  final Color avatarBg;
  final Color avatarFg;
  final Color ringColor;
  final bool champion;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final double outerDiameter = champion ? 72 : 60;
    return Container(
      width: outerDiameter,
      height: outerDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ringColor,
        border: Border.all(
          color: champion ? tokens.secondary : tokens.outline,
          width: champion ? 3 : tokens.borderWidth,
        ),
        boxShadow: champion
            ? <BoxShadow>[
                BoxShadow(
                  color: tokens.secondary.withValues(alpha: 0.5),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: MonogramAvatar(
        source: source,
        diameter: champion ? 60 : 52,
        backgroundColor: avatarBg,
        foregroundColor: avatarFg,
      ),
    );
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
            MonogramAvatar(
              source: row.name,
              diameter: 40,
              backgroundColor: you ? tokens.primary : tokens.secondary,
              foregroundColor: you ? Colors.white : tokens.onSecondary,
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
              MonogramAvatar(
                source: row.name,
                diameter: 40,
                backgroundColor: tokens.secondary,
                foregroundColor: tokens.onSecondary,
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
