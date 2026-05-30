import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/motion/count_up_number.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/identity_badge.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../models/attempt.dart';
import '../repositories/quiz_repository.dart';
import '../../session/storage/last_session_store.dart';

class QuizResultPage extends StatefulWidget {
  const QuizResultPage({super.key});

  @override
  State<QuizResultPage> createState() => _QuizResultPageState();
}

class _ResultPayload {
  const _ResultPayload({
    required this.attempt,
    required this.review,
    required this.source,
    this.syncError,
  });

  final Attempt attempt;
  final List<QuestionReview> review;
  final _ResultSource source;
  final String? syncError;
}

enum _ResultSource { freshFinalize, cachedSynced, cachedPending, none }

class _QuizResultPageState extends State<QuizResultPage> {
  late final QuizRepository _quizRepository;
  StreamSubscription<AttemptSubmittedEvent>? _attemptSubscription;
  StreamSubscription<RankedBadgeUnlockedEvent>? _badgeSubscription;
  Future<_ResultPayload>? _futureResult;
  bool _retryInFlight = false;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futureResult = _resolveResult();
    final EventBus bus = getIt<EventBus>();
    _attemptSubscription = bus.on<AttemptSubmittedEvent>().listen((_) {
      if (!mounted) return;
      // A background sync succeeded — swap the pending banner for the synced
      // state and show a positive confirmation.
      setState(() {
        _futureResult = _resolveResult();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Result synced to server.')),
      );
    });
    _badgeSubscription =
        bus.on<RankedBadgeUnlockedEvent>().listen(_onBadgeUnlocked);
  }

  @override
  void dispose() {
    _attemptSubscription?.cancel();
    _badgeSubscription?.cancel();
    super.dispose();
  }

  void _onBadgeUnlocked(RankedBadgeUnlockedEvent event) {
    if (!mounted) return;
    Haptics.celebrate();
    final tokens = context.arenaTokens;
    // In light mode primaryStrong is a deep purple (great with white text).
    // In dark mode primaryStrong is a *light* lilac — pair white with the dark
    // primarySoft surface instead so the badge toast stays WCAG AA legible.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color toastBackground =
        isDark ? tokens.primarySoft : tokens.primaryStrong;
    final String tierLabel = event.tier.isEmpty
        ? 'Medal'
        : '${event.tier[0].toUpperCase()}${event.tier.substring(1)}';
    final bool firstMedal = event.previousTier == 'none';
    final String message = firstMedal
        ? '$tierLabel badge unlocked!'
        : '$tierLabel badge unlocked — new personal best!';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: toastBackground,
          duration: const Duration(seconds: 4),
          content: Row(
            children: <Widget>[
              const Icon(
                Icons.emoji_events_rounded,
                color: Colors.white,
                size: MedRashIconSize.md,
              ),
              const SizedBox(width: MedRashSpace.sm),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<_ResultPayload> _resolveResult() async {
    final ActiveAttempt? active = _quizRepository.getActiveAttempt();

    if (active != null) {
      // We arrived via end-of-quiz navigation — finalize once.
      try {
        final Attempt attempt = await _quizRepository.finishAttempt();
        return _ResultPayload(
          attempt: attempt,
          review: _quizRepository.getLatestReview(),
          source: _ResultSource.freshFinalize,
          syncError: _quizRepository.cachedCompletedNeedsSync
              ? 'Result saved locally; sync to the server failed.'
              : null,
        );
      } on StateError catch (error) {
        // finalize threw (e.g. ranked already exists OR network failed). We
        // can still surface the locally-cached snapshot if it was persisted
        // before the throw — which is the case in our wrapper.
        final Attempt? cached = _quizRepository.getCachedCompletedAttempt();
        if (cached != null) {
          return _ResultPayload(
            attempt: cached,
            review: _quizRepository.getCachedCompletedReview(),
            source: _ResultSource.cachedPending,
            syncError: error.message,
          );
        }
        rethrow;
      }
    }

    // No active attempt → either page refresh or direct navigation.
    final Attempt? cached = _quizRepository.getCachedCompletedAttempt();
    if (cached != null) {
      return _ResultPayload(
        attempt: cached,
        review: _quizRepository.getCachedCompletedReview(),
        source: _quizRepository.cachedCompletedNeedsSync
            ? _ResultSource.cachedPending
            : _ResultSource.cachedSynced,
        syncError: _quizRepository.cachedCompletedNeedsSync
            ? 'Result saved locally; sync to the server failed.'
            : null,
      );
    }

    return const _ResultPayload(
      attempt: Attempt(
        score: 0,
        totalQuestions: 0,
        timeLabel: '00:00',
        modeLabel: 'Learning',
        timeTakenMs: 0,
      ),
      review: <QuestionReview>[],
      source: _ResultSource.none,
    );
  }

  Future<void> _retrySync() async {
    if (_retryInFlight) return;
    setState(() => _retryInFlight = true);
    try {
      await _quizRepository.retrySyncCachedAttempt();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Result synced to server.')),
      );
      setState(() {
        _futureResult = _resolveResult();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _retryInFlight = false);
      }
    }
  }

  Future<void> _goHome() async {
    // Clear the cached completed snapshot so the next attempt starts fresh.
    await _quizRepository.clearCachedCompletedAttempt();
    if (!mounted) return;
    context.go('/home');
  }

  VoidCallback? _resolveSessionLeaderboardCallback() {
    // Surface the per-session board only when the user reached the result
    // page via a session-launched quiz (LastSessionStore was stamped with a
    // sessionId on resolve). Falls back to null — the global leaderboard CTA
    // is always present so the surface never loses a forward action.
    final LastSessionStore store = getIt<LastSessionStore>();
    final LastSessionRecord? last = store.read();
    final String? sessionId = last?.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return null;
    }
    return () {
      Haptics.submit();
      context.push('/session-leaderboard/$sessionId');
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return ArenaScaffold(
      title: 'Quiz Result',
      showClose: true,
      actions: const <Widget>[IdentityBadge()],
      child: FutureBuilder<_ResultPayload>(
        future: _futureResult,
        builder: (BuildContext context, AsyncSnapshot<_ResultPayload> snapshot) {
          if (snapshot.hasError) {
            return _CenteredCallout(
              icon: Icons.error_rounded,
              iconColor: tokens.error,
              title: 'Something went wrong',
              body: snapshot.error.toString(),
              ctaLabel: 'Back To Home',
              onCta: _goHome,
            );
          }

          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: MedRashSkeletonCard(),
            );
          }

          final _ResultPayload payload = snapshot.data!;

          if (payload.source == _ResultSource.none) {
            return _CenteredCallout(
              icon: Icons.info_rounded,
              iconColor: tokens.primary,
              title: MedRashStrings.resultNoAttempt,
              body: 'Start a quiz from the home arena to see results here.',
              ctaLabel: MedRashStrings.resultBackToHome,
              onCta: _goHome,
            );
          }

          final Attempt attempt = payload.attempt;
          final List<QuestionReview> review = payload.review;
          final bool needsSync = payload.source == _ResultSource.cachedPending;
          final bool freshlySynced =
              payload.source == _ResultSource.cachedSynced ||
                  payload.source == _ResultSource.freshFinalize;

          return MedRashConstrainedBody(
            child: ListView(
              children: <Widget>[
                if (needsSync) ...<Widget>[
                  _PendingSyncBanner(
                    syncError: payload.syncError,
                    retryInFlight: _retryInFlight,
                    onRetry: _retryInFlight ? null : _retrySync,
                  ),
                  const SizedBox(height: MedRashSpace.lg),
                ] else if (freshlySynced) ...<Widget>[
                  const _SyncedBanner(),
                  const SizedBox(height: MedRashSpace.lg),
                ],
                _ScoreHeroCard(attempt: attempt),
                const SizedBox(height: MedRashSpace.lg),
                _CareerPointsBar(attempt: attempt),
                const SizedBox(height: MedRashSpace.xl),
                Text(
                  MedRashStrings.resultKnowledgeCheck,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                        letterSpacing: 0.6,
                      ),
                ),
                const SizedBox(height: MedRashSpace.md),
                ...review.asMap().entries.map(
                  (MapEntry<int, QuestionReview> entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: MedRashSpace.md),
                      child: _ReviewCard(
                        questionNumber: entry.key + 1,
                        review: entry.value,
                      ),
                    );
                  },
                ),
                const SizedBox(height: MedRashSpace.md),
                _WhatsNextCtas(
                  onLeaderboard: () {
                    Haptics.submit();
                    context.go('/leaderboard');
                  },
                  onHome: _goHome,
                  onSessionLeaderboard: _resolveSessionLeaderboardCallback(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScoreHeroCard extends StatelessWidget {
  const _ScoreHeroCard({required this.attempt});

  final Attempt attempt;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final int total = attempt.totalQuestions <= 0 ? 1 : attempt.totalQuestions;
    final int percent = ((attempt.score / total) * 100).round();
    final String headline = _headlineFor(attempt.score, attempt.totalQuestions);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusLarge + 4),
              gradient: LinearGradient(
                colors: <Color>[
                  tokens.primary.withValues(alpha: 0.28),
                  tokens.secondary.withValues(alpha: 0.28),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.primary.withValues(alpha: 0.22),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
        ),
        ArenaCard(
          padding: const EdgeInsets.all(MedRashSpace.xl),
          child: Semantics(
            container: true,
            label: 'Your score',
            value:
                '${attempt.score} out of ${attempt.totalQuestions}, time ${attempt.timeLabel}, mode ${attempt.modeLabel}',
            child: Column(
              children: <Widget>[
                Text(
                  headline.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.primaryStrong,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: MedRashSpace.md),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CountUpNumber(
                        value: attempt.score,
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        style: Theme.of(context)
                            .textTheme
                            .displayLarge
                            ?.copyWith(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800,
                              color: tokens.primary,
                              height: 1,
                            ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          ' / ${attempt.totalQuestions}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                color: tokens.textSecondary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MedRashSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MedRashSpace.lg,
                    vertical: MedRashSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.secondary,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: tokens.outline,
                      width: tokens.borderWidth,
                    ),
                  ),
                  child: CountUpNumber(
                    value: percent,
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    formatter: (int v) => '$v% CORRECT',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          color: tokens.onSecondary,
                          letterSpacing: 0.8,
                        ),
                  ),
                ),
                const SizedBox(height: MedRashSpace.lg),
                Wrap(
                  spacing: MedRashSpace.sm,
                  runSpacing: MedRashSpace.sm,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    _HeroMetricChip(
                      icon: Icons.timer_rounded,
                      label: attempt.timeLabel,
                      tint: tokens.primary,
                      surface: tokens.primarySoft,
                    ),
                    _HeroMetricChip(
                      icon: Icons.flag_rounded,
                      label: attempt.modeLabel,
                      tint: tokens.onSecondary,
                      surface: tokens.secondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _headlineFor(int score, int total) {
    if (total <= 0) return MedRashStrings.resultHeadline;
    final double ratio = score / total;
    if (ratio >= 1.0) return 'Perfect Run!';
    if (ratio >= 0.85) return 'Outstanding!';
    if (ratio >= 0.7) return 'Strong Attempt!';
    if (ratio >= 0.5) return 'Solid Effort';
    return MedRashStrings.resultHeadline;
  }
}

class _HeroMetricChip extends StatelessWidget {
  const _HeroMetricChip({
    required this.icon,
    required this.label,
    required this.tint,
    required this.surface,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.md,
        vertical: MedRashSpace.sm,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: tint, size: MedRashIconSize.md),
          const SizedBox(width: MedRashSpace.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _CareerPointsBar extends StatelessWidget {
  const _CareerPointsBar({required this.attempt});

  final Attempt attempt;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final int total = attempt.totalQuestions <= 0 ? 1 : attempt.totalQuestions;
    final double progress = (attempt.score / total).clamp(0.0, 1.0);
    final bool reducedMotion = MediaQuery.of(context).disableAnimations;
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.military_tech_rounded,
                color: tokens.primary,
                size: MedRashIconSize.md,
              ),
              const SizedBox(width: MedRashSpace.sm),
              Expanded(
                child: Text(
                  'Career points earned',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                ),
              ),
              CountUpNumber(
                value: attempt.score,
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                formatter: (int v) => '+$v',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: tokens.primaryStrong,
                    ),
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.md),
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: tokens.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: tokens.outline,
                width: tokens.borderWidth,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: TweenAnimationBuilder<double>(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: progress),
              builder: (BuildContext context, double value, Widget? _) {
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[tokens.primary, tokens.secondary],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.questionNumber, required this.review});

  final int questionNumber;
  final QuestionReview review;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool isCorrect = review.isCorrect;
    final Color accent = isCorrect ? tokens.success : tokens.error;
    final Color surface =
        isCorrect ? tokens.successSurface : tokens.dangerSurface;
    final String selectedOption = review.selectedIndex >= 0
        ? String.fromCharCode(65 + review.selectedIndex)
        : '\u2014';
    final String correctOption =
        String.fromCharCode(65 + review.question.correctIndex);
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isCorrect
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: accent,
                  size: MedRashIconSize.md,
                ),
              ),
              const SizedBox(width: MedRashSpace.md),
              Expanded(
                child: Text(
                  'Question $questionNumber',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                ),
              ),
              ArenaChip(
                label: isCorrect ? 'Correct' : 'Review',
                color: surface,
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.md),
          Text(
            review.question.prompt,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: MedRashSpace.md),
          Wrap(
            spacing: MedRashSpace.sm,
            runSpacing: MedRashSpace.sm,
            children: <Widget>[
              _AnswerPill(
                label: 'Your answer · $selectedOption',
                tint: accent,
                surface: surface,
              ),
              if (!isCorrect)
                _AnswerPill(
                  label: 'Correct · $correctOption',
                  tint: tokens.success,
                  surface: tokens.successSurface,
                ),
            ],
          ),
          const SizedBox(height: MedRashSpace.md),
          Container(
            padding: const EdgeInsets.all(MedRashSpace.md),
            decoration: BoxDecoration(
              color: tokens.primarySoft,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.lightbulb_rounded,
                  color: tokens.primaryStrong,
                  size: MedRashIconSize.md,
                ),
                const SizedBox(width: MedRashSpace.sm),
                Expanded(
                  child: Text(
                    review.question.explanation ??
                        'Review with facilitator for additional context.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.primaryStrong,
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerPill extends StatelessWidget {
  const _AnswerPill({
    required this.label,
    required this.tint,
    required this.surface,
  });

  final String label;
  final Color tint;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.md,
        vertical: MedRashSpace.xs + 2,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PendingSyncBanner extends StatelessWidget {
  const _PendingSyncBanner({
    required this.syncError,
    required this.retryInFlight,
    required this.onRetry,
  });

  final String? syncError;
  final bool retryInFlight;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.warningSurface,
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MedRashSpace.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: tokens.onSecondary,
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
            ),
            child: Text(
              MedRashStrings.resultPendingTag,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.warningSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
            ),
          ),
          const SizedBox(height: MedRashSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.cloud_off_rounded, color: tokens.onSecondary),
              const SizedBox(width: MedRashSpace.sm),
              Expanded(
                child: Text(
                  MedRashStrings.resultPendingMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.onSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          if (syncError != null) ...<Widget>[
            const SizedBox(height: MedRashSpace.sm),
            Text(
              syncError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.onSecondary,
                  ),
            ),
          ],
          const SizedBox(height: MedRashSpace.md),
          PressScale(
            enabled: !retryInFlight && onRetry != null,
            onTap: retryInFlight ? null : onRetry,
            child: ArenaButton(
              label: retryInFlight
                  ? MedRashStrings.resultRetryingLabel
                  : MedRashStrings.resultRetryLabel,
              icon: Icons.refresh_rounded,
              backgroundColor: tokens.secondary,
              foregroundColor: tokens.onSecondary,
              onPressed: retryInFlight ? null : onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncedBanner extends StatelessWidget {
  const _SyncedBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.successSurface,
      padding: const EdgeInsets.all(MedRashSpace.md),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MedRashSpace.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: tokens.success,
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
            ),
            child: Text(
              MedRashStrings.resultSavedTag,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
            ),
          ),
          const SizedBox(width: MedRashSpace.sm),
          Icon(Icons.cloud_done_rounded, color: tokens.success),
          const SizedBox(width: MedRashSpace.sm),
          Expanded(
            child: Text(
              MedRashStrings.resultSyncedMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsNextCtas extends StatelessWidget {
  const _WhatsNextCtas({
    required this.onLeaderboard,
    required this.onHome,
    this.onSessionLeaderboard,
  });

  final VoidCallback onLeaderboard;
  final VoidCallback onHome;

  /// When the user just finished a quiz launched from a session, the caller
  /// passes this to surface a dedicated "See how you ranked in this session"
  /// CTA above the global leaderboard button. Null hides the CTA.
  final VoidCallback? onSessionLeaderboard;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          "What's next",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
        ),
        const SizedBox(height: MedRashSpace.md),
        if (onSessionLeaderboard != null) ...<Widget>[
          PressScale(
            onTap: onSessionLeaderboard!,
            child: ArenaButton(
              label: 'See your session rank',
              icon: Icons.emoji_events_rounded,
              backgroundColor: tokens.primary,
              foregroundColor: Colors.white,
              onPressed: onSessionLeaderboard,
            ),
          ),
          const SizedBox(height: MedRashSpace.md),
        ],
        PressScale(
          onTap: onLeaderboard,
          child: ArenaButton(
            label: 'View Leaderboard',
            icon: Icons.leaderboard_rounded,
            backgroundColor: tokens.secondary,
            foregroundColor: tokens.onSecondary,
            onPressed: onLeaderboard,
          ),
        ),
        const SizedBox(height: MedRashSpace.md),
        PressScale(
          onTap: onHome,
          child: ArenaButton(
            label: MedRashStrings.resultBackToHome,
            icon: Icons.home_rounded,
            backgroundColor: tokens.primarySoft,
            foregroundColor: tokens.primaryStrong,
            onPressed: onHome,
          ),
        ),
      ],
    );
  }
}

class _CenteredCallout extends StatelessWidget {
  const _CenteredCallout({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onCta,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Center(
      child: ArenaCard(
        padding: const EdgeInsets.all(MedRashSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: iconColor, size: MedRashIconSize.xl),
            const SizedBox(height: MedRashSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
            ),
            const SizedBox(height: MedRashSpace.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
            const SizedBox(height: MedRashSpace.lg),
            PressScale(
              onTap: onCta,
              child: ArenaButton(
                label: ctaLabel,
                icon: Icons.home_rounded,
                backgroundColor: tokens.secondary,
                foregroundColor: tokens.onSecondary,
                onPressed: onCta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
