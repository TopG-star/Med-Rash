import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/ui/identity_badge.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/theme/theme_extensions.dart';
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
          period: _allTime ? LeaderboardPeriod.allTime : LeaderboardPeriod.monthly,
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
    setState(() {
      _allTime = allTime;
      _futureRows = _leaderboardRepository.fetchLeaderboard(
        period: allTime ? LeaderboardPeriod.allTime : LeaderboardPeriod.monthly,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return ArenaScaffold(
      title: MedRashStrings.leaderboardTitle,
      showBack: true,
      bottomNav: true,
      actions: const <Widget>[IdentityBadge()],
      child: FutureBuilder<List<LeaderboardRow>>(
        future: _futureRows,
        builder: (BuildContext context, AsyncSnapshot<List<LeaderboardRow>> snapshot) {
          if (!snapshot.hasData) {
            return const MedRashConstrainedBody(
              child: MedRashSkeletonList(),
            );
          }

          final List<LeaderboardRow> rows = snapshot.data!;
          final List<LeaderboardRow> podium = rows.take(3).toList();
          final List<LeaderboardRow> rest = rows.skip(3).toList();

          return MedRashConstrainedBody(
            child: ListView(
            children: <Widget>[
              ArenaCard(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _SegmentButton(
                        label: MedRashStrings.leaderboardMonthly,
                        selected: !_allTime,
                        onTap: () => _switchPeriod(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SegmentButton(
                        label: MedRashStrings.leaderboardAllTime,
                        selected: _allTime,
                        onTap: () => _switchPeriod(true),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (podium.length >= 3)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(child: _PodiumCard(row: podium[1], color: tokens.secondary, height: 220)),
                    const SizedBox(width: 12),
                    Expanded(child: _PodiumCard(row: podium[0], color: tokens.primary, height: 250, champion: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _PodiumCard(row: podium[2], color: tokens.tertiary, height: 220)),
                  ],
                ),
              const SizedBox(height: 24),
              ...rest.map(
                (LeaderboardRow row) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                    container: true,
                    label: row.isCurrentUser
                        ? 'Rank ${row.rank}, you, ${row.name}'
                        : 'Rank ${row.rank}, ${row.name}',
                    value: '${row.score} points',
                    child: ArenaCard(
                      color: row.isCurrentUser ? tokens.primary : tokens.surface,
                      child: Row(
                        children: <Widget>[
                          Text('#${row.rank}', style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(width: 16),
                          const CircleAvatar(child: Icon(Icons.person)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              row.isCurrentUser ? '${row.name} (YOU)' : row.name,
                              style: Theme.of(context).textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${row.score}', style: Theme.of(context).textTheme.headlineMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            ),
          );
        },
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
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
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? tokens.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: selected ? Colors.white : tokens.textPrimary,
                ),
          ),
        ),
      ),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.row,
    required this.color,
    required this.height,
    this.champion = false,
  });

  final LeaderboardRow row;
  final Color color;
  final double height;
  final bool champion;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: ArenaCard(
        color: color,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            if (champion)
              const Positioned(
                top: -10,
                right: -4,
                child: CircleAvatar(
                  child: Icon(Icons.star, size: 18),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('#${row.rank}', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 16),
                const CircleAvatar(radius: 32, child: Icon(Icons.person)),
                const SizedBox(height: 16),
                Text(
                  row.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text('${row.score}', style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}