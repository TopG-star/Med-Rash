import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/empty_state.dart';
import '../../../core/ui/widgets/gamified_avatar.dart';
import '../../profile/models/avatar_spec.dart';
import '../models/session_leaderboard_row.dart';
import '../repositories/leaderboard_repository.dart';

/// Live leaderboard for one session. Polls every [_pollInterval] while the
/// session is live; once the server reports `isLive=false` (ends_at passed
/// or admin stamped closed_at) polling halts and the table is frozen.
///
/// Gating is server-enforced: callers who haven't played at least one
/// attempt in this session get a 403 NOT_SESSION_PARTICIPANT, which the
/// repo surfaces as `result.notAParticipant` so we show a play-first prompt
/// instead of an empty list.
class SessionLiveLeaderboardPage extends StatefulWidget {
  const SessionLiveLeaderboardPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionLiveLeaderboardPage> createState() =>
      _SessionLiveLeaderboardPageState();
}

class _SessionLiveLeaderboardPageState
    extends State<SessionLiveLeaderboardPage> {
  static const Duration _pollInterval = Duration(seconds: 12);
  static const Duration _tickInterval = Duration(seconds: 1);

  late final LeaderboardRepository _repository;
  Timer? _pollTimer;
  Timer? _tickTimer;
  bool _loading = true;
  SessionLeaderboardResult? _result;
  Object? _error;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _repository = getIt<LeaderboardRepository>();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final SessionLeaderboardResult result =
          await _repository.fetchSessionLeaderboard(
        sessionId: widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = null;
        _loading = false;
        _now = DateTime.now();
      });
      _schedulePollIfLive(result);
      _scheduleTickIfCountdown(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
      // Back off polling on hard errors so we don't hammer the gate; the
      // user can pull-to-refresh / re-enter to retry manually.
      _pollTimer?.cancel();
      _pollTimer = null;
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  void _schedulePollIfLive(SessionLeaderboardResult result) {
    _pollTimer?.cancel();
    if (!result.isLive) {
      _pollTimer = null;
      return;
    }
    _pollTimer = Timer(_pollInterval, _refresh);
  }

  void _scheduleTickIfCountdown(SessionLeaderboardResult result) {
    _tickTimer?.cancel();
    if (!result.isLive || result.endsAt == null) {
      _tickTimer = null;
      return;
    }
    _tickTimer = Timer.periodic(_tickInterval, (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'SESSION LEADERBOARD',
      showBack: true,
      bottomNav: true,
      fallbackRoute: '/home',
      child: MedRashConstrainedBody(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const MedRashSkeletonList();
    }
    if (_error != null && _result == null) {
      return _ErrorState(
        message: 'Couldn\'t load the leaderboard. Please try again.',
        onRetry: _handleManualRetry,
      );
    }
    final SessionLeaderboardResult result = _result!;
    if (result.notAParticipant) {
      return _NotAParticipantState(onRetry: _handleManualRetry);
    }
    if (result.rows.isEmpty) {
      return _EmptyState(isLive: result.isLive);
    }

    return RefreshIndicator(
      onRefresh: _handleManualRetry,
      child: ListView(
        padding: const EdgeInsets.only(bottom: MedRashSpace.xl),
        children: <Widget>[
          _StatusBanner(result: result, now: _now),
          const SizedBox(height: MedRashSpace.md),
          for (final SessionLeaderboardRow row in result.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: MedRashSpace.sm),
              child: _SessionRow(row: row),
            ),
          if (result.me != null &&
              !result.rows.any(
                (SessionLeaderboardRow r) => r.userId == result.me!.userId,
              )) ...<Widget>[
            const SizedBox(height: MedRashSpace.md),
            Text(
              'YOUR RANK',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    color: context.arenaTokens.textSecondary,
                    letterSpacing: 1.0,
                  ),
            ),
            const SizedBox(height: MedRashSpace.xs),
            _SessionRow(row: result.me!),
          ],
          if (!result.isLive) ...<Widget>[
            const SizedBox(height: MedRashSpace.lg),
            _GlobalStatsCta(
              onTap: () => context.go('/leaderboard'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleManualRetry() async {
    setState(() {
      _loading = _result == null;
    });
    await _refresh();
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.result, required this.now});

  final SessionLeaderboardResult result;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool isLive = result.isLive;
    final String label = isLive ? 'LIVE SESSION' : 'SESSION ENDED';
    final Color dot = isLive ? tokens.success : tokens.textSecondary;
    final String? countdown = _countdown(result, now);
    final bool urgent = isLive && countdown != null && _isUrgent(result, now);
    final Color timerColor = !isLive
        ? tokens.textSecondary
        : (urgent ? tokens.error : tokens.primary);

    return ArenaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.md,
        vertical: MedRashSpace.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: MedRashSpace.sm),
                    Text(
                      label,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: tokens.textPrimary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: MedRashSpace.xs),
                Text(
                  isLive
                      ? 'Refreshes every 12s'
                      : 'Final standings',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          if (countdown != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MedRashSpace.md,
                vertical: MedRashSpace.xs,
              ),
              decoration: BoxDecoration(
                color: urgent ? tokens.dangerSurface : tokens.primarySoft,
                borderRadius: BorderRadius.circular(tokens.radiusLarge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: timerColor,
                  ),
                  const SizedBox(width: MedRashSpace.xs),
                  Text(
                    countdown,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          fontWeight: FontWeight.w800,
                          color: timerColor,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String? _countdown(SessionLeaderboardResult result, DateTime now) {
    final DateTime? endsAt = result.endsAt;
    if (endsAt == null) return null;
    final Duration remaining = endsAt.difference(now);
    if (remaining.isNegative) return '00:00';
    final int totalSeconds = remaining.inSeconds;
    final int mins = totalSeconds ~/ 60;
    final int secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static bool _isUrgent(SessionLeaderboardResult result, DateTime now) {
    final DateTime? endsAt = result.endsAt;
    if (endsAt == null) return false;
    final Duration remaining = endsAt.difference(now);
    return remaining.inSeconds <= 60;
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.row});

  final SessionLeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool me = row.isCurrentUser;
    final bool topRank = row.rank == 1;

    final Color cardColor = me ? tokens.primary : tokens.surface;
    final Color titleColor = me ? Colors.white : tokens.textPrimary;
    final Color subtitleColor = me
        ? Colors.white.withValues(alpha: 0.85)
        : tokens.textSecondary;
    final Color scoreColor = me ? Colors.white : tokens.success;
    final Color scoreCaptionColor = me
        ? Colors.white.withValues(alpha: 0.75)
        : tokens.textSecondary;

    final Widget row1 = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _RankBadge(rank: row.rank, isCurrentUser: me, topRank: topRank),
        const SizedBox(width: MedRashSpace.sm),
        _AvatarRing(
          name: row.name,
          userId: row.userId,
          topRank: topRank,
          isCurrentUser: me,
        ),
        const SizedBox(width: MedRashSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                me ? '${row.name} (you)' : row.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                me
                    ? 'CURRENT STANDING'
                    : (topRank
                        ? 'TOP PERFORMER · ${_formatTime(row.timeTakenMs)}'
                        : _formatTime(row.timeTakenMs)),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: subtitleColor,
                      fontWeight: me || topRank
                          ? FontWeight.w700
                          : FontWeight.w500,
                      letterSpacing: 0.6,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              _formatScore(row.sessionScore),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
            ),
            Text(
              'pts',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scoreCaptionColor,
                  ),
            ),
          ],
        ),
      ],
    );

    final Widget card = ArenaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.md,
        vertical: MedRashSpace.sm,
      ),
      color: cardColor,
      child: row1,
    );

    if (!me) return card;
    // Lift the current user's row slightly so it pops against neighbours,
    // mirroring the reference design's "current standing" emphasis.
    return Transform.scale(scale: 1.015, child: card);
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '—';
    final int totalSeconds = (ms / 1000).round();
    final int mins = totalSeconds ~/ 60;
    final int secs = totalSeconds % 60;
    if (mins <= 0) return '${secs}s';
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  String _formatScore(int score) {
    final String s = score.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({
    required this.rank,
    required this.isCurrentUser,
    required this.topRank,
  });

  final int rank;
  final bool isCurrentUser;
  final bool topRank;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    // Gold trophy for #1, solid muted circle for ranks 2-3, hollow outline for 4+.
    final bool solid = rank <= 3;
    final Color background = isCurrentUser
        ? Colors.white.withValues(alpha: 0.18)
        : (topRank
            ? tokens.warningSurface
            : (solid ? tokens.surfaceMuted : Colors.transparent));
    final Color foreground = isCurrentUser
        ? Colors.white
        : (topRank ? tokens.tertiary : tokens.textPrimary);
    final Border? border = (!solid && !isCurrentUser)
        ? Border.all(color: tokens.outlineMuted, width: 1.5)
        : null;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: border,
      ),
      alignment: Alignment.center,
      child: topRank
          ? Icon(Icons.emoji_events_rounded, size: 20, color: foreground)
          : Text(
              '$rank',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
            ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({
    required this.name,
    required this.userId,
    required this.topRank,
    required this.isCurrentUser,
  });

  final String name;

  /// Stable per-user seed used for the Navii mascot. Empty/null falls back
  /// to the monogram of [name].
  final String? userId;
  final bool topRank;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color ringColor = isCurrentUser
        ? Colors.white
        : (topRank ? tokens.tertiary : tokens.outlineMuted);
    final double ringWidth = (isCurrentUser || topRank) ? 2 : 1;
    final String? seed = userId;
    return GamifiedAvatar(
      spec: (seed != null && seed.isNotEmpty)
          ? NaviiAvatarSpec(seed: seed, fallbackSource: name)
          : MonogramAvatarSpec(source: name),
      diameter: 44,
      ringWidth: ringWidth,
      ringGradient: LinearGradient(
        colors: <Color>[ringColor, ringColor],
      ),
    );
  }
}

class _GlobalStatsCta extends StatelessWidget {
  const _GlobalStatsCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Column(
      children: <Widget>[
        PressScale(
          onTap: onTap,
          child: ArenaButton(
            label: 'Continue to global ranking',
            icon: Icons.arrow_forward_rounded,
            backgroundColor: tokens.primary,
            foregroundColor: Colors.white,
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: MedRashSpace.sm),
        Text(
          'GLOBAL RANKING WILL UPDATE INSTANTLY',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return MedRashEmptyState(
      icon: Icons.timer_outlined,
      title: isLive ? 'No submissions yet' : 'Session ended',
      body: isLive
          ? 'As participants finish the quiz they\'ll appear here, ranked by score then speed.'
          : 'No completed attempts were recorded for this session.',
    );
  }
}

class _NotAParticipantState extends StatelessWidget {
  const _NotAParticipantState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const MedRashEmptyState(
          icon: Icons.lock_outline,
          title: 'Play first to see the board',
          body:
              'Take this session\'s quiz in ranked mode, then your standing and everyone else\'s will appear here.',
        ),
        const SizedBox(height: MedRashSpace.md),
        ElevatedButton.icon(
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Back to home'),
        ),
        const SizedBox(height: MedRashSpace.sm),
        TextButton(
          onPressed: onRetry,
          child: const Text('I just played — refresh'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        MedRashEmptyState(
          icon: Icons.signal_wifi_off,
          title: 'Connection hiccup',
          body: message,
        ),
        const SizedBox(height: MedRashSpace.md),
        ElevatedButton(
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    );
  }
}
