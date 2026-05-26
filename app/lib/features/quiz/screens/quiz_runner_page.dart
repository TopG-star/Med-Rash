import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/quiz_progress_bar.dart';
import '../../../core/theme/theme_extensions.dart';
import '../models/question.dart';
import '../models/quiz.dart';
import '../repositories/quiz_repository.dart';

class QuizRunnerPage extends StatefulWidget {
  const QuizRunnerPage({super.key});

  @override
  State<QuizRunnerPage> createState() => _QuizRunnerPageState();
}

enum _PreparationOutcome { ready, backendOffline, qrSessionUnavailable, noQuizAvailable }

class _PreparationResult {
  const _PreparationResult({
    required this.outcome,
    this.error,
  });

  final _PreparationOutcome outcome;
  final Object? error;
}

class _QuizRunnerPageState extends State<QuizRunnerPage> {
  late final QuizRepository _quizRepository;
  Future<_PreparationResult>? _futurePreparation;
  int _selectedIndex = -1;
  bool _retryInFlight = false;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futurePreparation = _prepareAttempt();
  }

  Future<_PreparationResult> _prepareAttempt({bool allowOfflinePractice = false}) async {
    // 1. If we already have an active (possibly resumed) attempt, use it.
    final ActiveAttempt? existing = _quizRepository.getActiveAttempt();
    if (existing != null) {
      return const _PreparationResult(outcome: _PreparationOutcome.ready);
    }

    // 2. No active attempt → ensure live data, then auto-start the first quiz
    //    in learning mode as the open-access fallback entry.
    try {
      await _quizRepository.ensureLiveDataReady();
    } catch (error) {
      return _PreparationResult(
        outcome: _PreparationOutcome.backendOffline,
        error: error,
      );
    }

    List<Quiz> quizzes;
    try {
      quizzes = await _quizRepository.fetchActiveQuizzes();
    } catch (error) {
      return _PreparationResult(
        outcome: _PreparationOutcome.backendOffline,
        error: error,
      );
    }

    if (quizzes.isEmpty) {
      return const _PreparationResult(outcome: _PreparationOutcome.noQuizAvailable);
    }

    try {
      await _quizRepository.startAttempt(
        quizId: quizzes.first.id,
        mode: QuizMode.learning,
        allowOfflinePractice: allowOfflinePractice,
      );
      return const _PreparationResult(outcome: _PreparationOutcome.ready);
    } on StateError catch (error) {
      return _PreparationResult(
        outcome: _PreparationOutcome.backendOffline,
        error: error,
      );
    }
  }

  Future<void> _retryConnection() async {
    if (_retryInFlight) return;
    setState(() => _retryInFlight = true);
    _PreparationResult result;
    try {
      result = await _prepareAttempt();
    } catch (error) {
      result = _PreparationResult(
        outcome: _PreparationOutcome.backendOffline,
        error: error,
      );
    }
    if (!mounted) return;
    setState(() {
      _futurePreparation = Future<_PreparationResult>.value(result);
      _retryInFlight = false;
    });
  }

  Future<void> _startOfflinePractice() async {
    if (_retryInFlight) return;
    setState(() => _retryInFlight = true);
    try {
      final _PreparationResult result =
          await _prepareAttempt(allowOfflinePractice: true);
      if (!mounted) return;
      setState(() {
        _futurePreparation = Future<_PreparationResult>.value(result);
        _retryInFlight = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _retryInFlight = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start offline practice: $error')),
      );
    }
  }

  Future<void> _restartAttempt() async {
    await _quizRepository.restartActiveAttempt();
    if (!mounted) return;
    setState(() {
      _selectedIndex = -1;
      _futurePreparation = Future<_PreparationResult>.value(
        const _PreparationResult(outcome: _PreparationOutcome.ready),
      );
    });
  }

  Future<void> _submitCurrentAnswer() async {
    if (_selectedIndex < 0) return;

    _quizRepository.selectAnswer(_selectedIndex);
    final bool isLastQuestion = await _quizRepository.submitCurrentAnswer();

    if (!mounted) return;

    if (isLastQuestion) {
      context.go('/result');
      return;
    }

    setState(() => _selectedIndex = -1);
  }

  Widget _buildOfflineInterstitial({required bool allowOfflineOption, required Object? error}) {
    final tokens = context.arenaTokens;
    final String detail = error?.toString() ?? 'Connection to the backend failed.';
    return Center(
      child: ArenaCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(
              'Backend offline',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              allowOfflineOption
                  ? 'We could not reach the MedRash backend. You can retry, '
                      'or run a practice attempt that will NOT be recorded.'
                  : 'This QR session needs the backend to be reachable. '
                      'Please retry once your connection is restored.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ArenaCard(
              color: const Color(0xFFF8F8F8),
              child: Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 20),
            ArenaButton(
              label: _retryInFlight ? 'Retrying…' : 'Retry connection',
              icon: Icons.refresh_rounded,
              backgroundColor: tokens.primary,
              onPressed: _retryInFlight ? null : _retryConnection,
            ),
            if (allowOfflineOption) ...<Widget>[
              const SizedBox(height: 12),
              ArenaButton(
                label: 'Practice offline (not recorded)',
                icon: Icons.school_rounded,
                backgroundColor: tokens.secondary,
                onPressed: _retryInFlight ? null : _startOfflinePractice,
              ),
            ],
            const SizedBox(height: 12),
            ArenaButton(
              label: 'Back To Home',
              icon: Icons.home_rounded,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return ArenaScaffold(
      title: 'Quiz',
      showClose: true,
      child: FutureBuilder<_PreparationResult>(
        future: _futurePreparation,
        builder: (BuildContext context, AsyncSnapshot<_PreparationResult> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildOfflineInterstitial(
              allowOfflineOption: true,
              error: snapshot.error,
            );
          }

          final _PreparationResult prep =
              snapshot.data ?? const _PreparationResult(outcome: _PreparationOutcome.ready);

          if (prep.outcome == _PreparationOutcome.backendOffline ||
              prep.outcome == _PreparationOutcome.qrSessionUnavailable) {
            return _buildOfflineInterstitial(
              allowOfflineOption:
                  prep.outcome == _PreparationOutcome.backendOffline,
              error: prep.error,
            );
          }

          final ActiveAttempt? attempt = _quizRepository.getActiveAttempt();
          final Question? question = _quizRepository.getCurrentQuestion();

          if (attempt == null || question == null) {
            return Center(
              child: ArenaButton(
                label: 'Back To Home',
                icon: Icons.home_rounded,
                onPressed: () => context.go('/home'),
              ),
            );
          }

          final double progress =
              (attempt.currentQuestionIndex + 1) / attempt.totalQuestions.toDouble();

          return ListView(
            children: <Widget>[
              if (attempt.isResumed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ArenaCard(
                    color: const Color(0xFFE6F4FF),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.restart_alt_rounded),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Resumed your attempt where you left off.'),
                        ),
                        TextButton(
                          onPressed: _restartAttempt,
                          child: const Text('Restart attempt'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (attempt.isOfflinePractice)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: ArenaCard(
                    color: Color(0xFFFFF4E0),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.cloud_off_rounded),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Offline practice — this attempt will NOT be recorded.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: <Widget>[
                  Text(
                    'Question ${attempt.currentQuestionIndex + 1} of ${attempt.totalQuestions}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  Text(
                    attempt.mode == QuizMode.ranked ? 'Ranked' : 'Learning',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              QuizProgressBar(progress: progress),
              const SizedBox(height: 24),
              Center(child: ArenaChip(label: attempt.quiz.category)),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final MediaQueryData mq = MediaQuery.of(context);
                  final bool landscape = mq.orientation == Orientation.landscape &&
                      constraints.maxWidth >= 600;

                  final Widget promptBlock = Text(
                    question.prompt,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: landscape ? TextAlign.start : TextAlign.center,
                  );

                  final List<Widget> optionTiles = List<Widget>.generate(
                    question.options.length,
                    (int index) {
                      final bool selected = _selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _selectedIndex = index),
                            borderRadius: BorderRadius.circular(tokens.radiusLarge),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: ArenaCard(
                                color: selected ? tokens.primary : tokens.surface,
                                child: Row(
                                  children: <Widget>[
                                    CircleAvatar(
                                      backgroundColor: selected
                                          ? tokens.textPrimary
                                          : tokens.surfaceMuted,
                                      child: Text(
                                        String.fromCharCode(65 + index),
                                        style: TextStyle(
                                          color: selected
                                              ? tokens.primary
                                              : tokens.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        question.options[index],
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );

                  if (landscape) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: ArenaCard(
                            color: const Color(0xFFF8F8F8),
                            child: promptBlock,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: optionTiles,
                          ),
                        ),
                      ],
                    );
                  }

                  return ArenaCard(
                    color: const Color(0xFFF8F8F8),
                    child: Column(
                      children: <Widget>[
                        promptBlock,
                        const SizedBox(height: 24),
                        ...optionTiles,
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              ArenaButton(
                label: 'Submit Answer',
                icon: Icons.arrow_forward_rounded,
                backgroundColor: tokens.secondary,
                onPressed: _selectedIndex >= 0 ? _submitCurrentAnswer : null,
              ),
            ],
          );
        },
      ),
    );
  }
}