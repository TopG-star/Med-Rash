import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/empty_state.dart';
import '../../../core/ui/widgets/monogram_avatar.dart';
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

  late final LeaderboardRepository _repository;
  Timer? _pollTimer;
  bool _loading = true;
  SessionLeaderboardResult? _result;
  Object? _error;

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
      });
      _schedulePollIfLive(result);
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
          _StatusBanner(result: result),
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
  const _StatusBanner({required this.result});

  final SessionLeaderboardResult result;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool isLive = result.isLive;
    final String label = isLive ? 'LIVE' : 'ENDED';
    final Color dot = isLive ? tokens.success : tokens.textSecondary;
    return ArenaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.md,
        vertical: MedRashSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: MedRashSpace.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
          ),
          const Spacer(),
          Text(
            isLive ? 'Refreshes every 12s' : 'Final standings',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.row});

  final SessionLeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool me = row.isCurrentUser;
    return ArenaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.md,
        vertical: MedRashSpace.sm,
      ),
      color: me ? tokens.successSurface : null,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            child: Text(
              '#${row.rank}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: MedRashSpace.sm),
          MonogramAvatar(source: row.name, diameter: 36),
          const SizedBox(width: MedRashSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  me ? '${row.name} (you)' : row.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatTime(row.timeTakenMs),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Text(
            '${row.sessionScore}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '—';
    final int totalSeconds = (ms / 1000).round();
    final int mins = totalSeconds ~/ 60;
    final int secs = totalSeconds % 60;
    if (mins <= 0) return '${secs}s';
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
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
