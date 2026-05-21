import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/ui/identity_badge.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/theme/theme_extensions.dart';
import '../models/attempt.dart';
import '../repositories/quiz_repository.dart';

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
  Future<_ResultPayload>? _futureResult;
  bool _retryInFlight = false;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futureResult = _resolveResult();
    _attemptSubscription =
        getIt<EventBus>().on<AttemptSubmittedEvent>().listen((_) {
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
  }

  @override
  void dispose() {
    _attemptSubscription?.cancel();
    super.dispose();
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
            return Center(
              child: ArenaCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.error_outline),
                    const SizedBox(height: 12),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ArenaButton(
                      label: 'Back To Home',
                      icon: Icons.home_outlined,
                      onPressed: _goHome,
                    ),
                  ],
                ),
              ),
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
            return Center(
              child: ArenaCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.info_outline),
                    const SizedBox(height: 12),
                    const Text(
                      'No completed attempt to display.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ArenaButton(
                      label: 'Back To Home',
                      icon: Icons.home_outlined,
                      onPressed: _goHome,
                    ),
                  ],
                ),
              ),
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
                ArenaCard(
                  color: tokens.warningSurface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.cloud_off_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Saved on this device. We\u2019ll keep retrying in the background \u2014 your score is not lost.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      if (payload.syncError != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          payload.syncError!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      ArenaButton(
                        label: _retryInFlight ? 'Retrying…' : 'Retry now',
                        icon: Icons.refresh,
                        backgroundColor: tokens.secondary,
                        onPressed: _retryInFlight ? null : _retrySync,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (freshlySynced) ...<Widget>[
                ArenaCard(
                  color: tokens.successSurface,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.cloud_done_outlined, color: tokens.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Saved and synced to MedRash.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ArenaCard(
                color: tokens.primary,
                child: Column(
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('GREAT EFFORT!',
                          style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    const SizedBox(height: 20),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${attempt.score}/${attempt.totalQuestions}',
                          style: Theme.of(context).textTheme.displayLarge),
                    ),
                    const SizedBox(height: 20),
                    ArenaCard(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.timer_outlined),
                          const SizedBox(width: 8),
                          Text('Time: ${attempt.timeLabel} | ${attempt.modeLabel}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('KNOWLEDGE CHECK', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              ...review.asMap().entries.map(
                (MapEntry<int, QuestionReview> entry) {
                  final int questionNumber = entry.key + 1;
                  final QuestionReview item = entry.value;
                  final String selectedOption = item.selectedIndex >= 0
                      ? String.fromCharCode(65 + item.selectedIndex)
                      : 'No response';
                  final String correctOption =
                      String.fromCharCode(65 + item.question.correctIndex);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ArenaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                item.isCorrect
                                    ? Icons.check_circle_outline
                                    : Icons.cancel_outlined,
                                color: item.isCorrect ? tokens.success : tokens.error,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Question $questionNumber',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(item.question.prompt,
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: 12),
                          Text(
                            'You selected $selectedOption, correct answer is $correctOption.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 12),
                          ArenaCard(
                            color: const Color(0xFFF8F8F8),
                            child: Text(
                              'Explanation: ${item.question.explanation ?? 'Review with facilitator for additional context.'}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ArenaButton(
                label: 'Retry Learning',
                icon: Icons.replay,
                backgroundColor: Colors.white,
                onPressed: _goHome,
              ),
              const SizedBox(height: 16),
              ArenaButton(
                label: 'View Leaderboard',
                icon: Icons.bar_chart,
                backgroundColor: tokens.secondary,
                onPressed: () => context.go('/leaderboard'),
              ),
            ],
            ),
          );
        },
      ),
    );
  }
}