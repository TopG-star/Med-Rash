import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/quiz_progress_bar.dart';
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

/// Snapshot of a freshly-submitted answer used to drive the correct/wrong
/// flash. We hold the captured question + indices on state so the rebuild
/// after submit shows the just-answered question (not the next one) until
/// the flash window closes.
class _AnswerFlash {
  const _AnswerFlash({
    required this.question,
    required this.selectedIndex,
    required this.correctIndex,
  });

  final Question question;
  final int selectedIndex;
  final int correctIndex;

  bool get isCorrect => selectedIndex == correctIndex;
}

class _QuizRunnerPageState extends State<QuizRunnerPage> {
  late final QuizRepository _quizRepository;
  Future<_PreparationResult>? _futurePreparation;
  int _selectedIndex = -1;
  bool _retryInFlight = false;
  _AnswerFlash? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futurePreparation = _prepareAttempt();
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
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
      _flash = null;
      _flashTimer?.cancel();
      _flashTimer = null;
      _futurePreparation = Future<_PreparationResult>.value(
        const _PreparationResult(outcome: _PreparationOutcome.ready),
      );
    });
  }

  void _onSelectOption(int index) {
    if (_flash != null) return;
    Haptics.selection();
    setState(() => _selectedIndex = index);
  }

  Future<void> _submitCurrentAnswer() async {
    if (_selectedIndex < 0 || _flash != null) return;

    final Question? captured = _quizRepository.getCurrentQuestion();
    if (captured == null) return;

    final int selected = _selectedIndex;
    final bool isCorrect = selected == captured.correctIndex;

    _quizRepository.selectAnswer(selected);

    // Trigger flash + haptic *before* awaiting submit so the user gets
    // immediate feedback even if the repository write is slow.
    setState(() {
      _flash = _AnswerFlash(
        question: captured,
        selectedIndex: selected,
        correctIndex: captured.correctIndex,
      );
    });
    if (isCorrect) {
      Haptics.celebrate();
    } else {
      Haptics.submit();
    }

    final bool isLastQuestion = await _quizRepository.submitCurrentAnswer();
    if (!mounted) return;

    final bool reducedMotion = MediaQuery.of(context).disableAnimations;
    final Duration holdFor = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 700);

    _flashTimer?.cancel();
    _flashTimer = Timer(holdFor, () {
      if (!mounted) return;
      if (isLastQuestion) {
        context.go('/result');
        return;
      }
      setState(() {
        _flash = null;
        _selectedIndex = -1;
      });
    });
  }

  Widget _buildOfflineInterstitial({required bool allowOfflineOption, required Object? error}) {
    final tokens = context.arenaTokens;
    final String detail = error?.toString() ?? 'Connection to the backend failed.';
    return Center(
      child: ArenaCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: MedRashIconSize.xl,
              color: tokens.primary,
            ),
            const SizedBox(height: MedRashSpace.md),
            Text(
              'Backend offline',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
            ),
            const SizedBox(height: MedRashSpace.md),
            Text(
              allowOfflineOption
                  ? 'We could not reach the MedRash backend. You can retry, '
                      'or run a practice attempt that will NOT be recorded.'
                  : 'This QR session needs the backend to be reachable. '
                      'Please retry once your connection is restored.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
            const SizedBox(height: MedRashSpace.md),
            ArenaCard(
              color: tokens.surfaceMuted,
              padding: const EdgeInsets.all(MedRashSpace.md),
              child: Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
              ),
            ),
            const SizedBox(height: MedRashSpace.lg),
            PressScale(
              enabled: !_retryInFlight,
              onTap: _retryInFlight ? null : _retryConnection,
              child: ArenaButton(
                label: _retryInFlight ? 'Retrying\u2026' : 'Retry connection',
                icon: Icons.refresh_rounded,
                backgroundColor: tokens.secondary,
                foregroundColor: tokens.onSecondary,
                onPressed: _retryInFlight ? null : _retryConnection,
              ),
            ),
            if (allowOfflineOption) ...<Widget>[
              const SizedBox(height: MedRashSpace.md),
              PressScale(
                enabled: !_retryInFlight,
                onTap: _retryInFlight ? null : _startOfflinePractice,
                child: ArenaButton(
                  label: 'Practice offline (not recorded)',
                  icon: Icons.school_rounded,
                  backgroundColor: tokens.primarySoft,
                  foregroundColor: tokens.primaryStrong,
                  onPressed: _retryInFlight ? null : _startOfflinePractice,
                ),
              ),
            ],
            const SizedBox(height: MedRashSpace.md),
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
            return Center(child: CircularProgressIndicator(color: tokens.primary));
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
          // During a flash the captured question stays on screen even though
          // the repository has already advanced to the next index.
          final Question? liveQuestion = _quizRepository.getCurrentQuestion();
          final Question? question = _flash?.question ?? liveQuestion;

          if (attempt == null || question == null) {
            return Center(
              child: ArenaButton(
                label: 'Back To Home',
                icon: Icons.home_rounded,
                onPressed: () => context.go('/home'),
              ),
            );
          }

          // Progress fills as the participant works through the deck; during
          // the flash we want the bar to already reflect the just-submitted
          // answer so the next-question reveal feels earned.
          final int displayedIndex = _flash != null
              ? attempt.currentQuestionIndex // already advanced post-submit
              : attempt.currentQuestionIndex + 1;
          final double progress =
              displayedIndex.clamp(0, attempt.totalQuestions) /
                  attempt.totalQuestions.toDouble();

          return ListView(
            children: <Widget>[
              if (attempt.isResumed) _ResumedBanner(onRestart: _restartAttempt),
              if (attempt.isOfflinePractice) const _OfflinePracticeBanner(),
              Row(
                children: <Widget>[
                  Text(
                    'Question ${attempt.currentQuestionIndex + 1} of ${attempt.totalQuestions}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                  ),
                  const Spacer(),
                  ArenaChip(
                    label: attempt.mode == QuizMode.ranked ? 'Ranked' : 'Learning',
                    color: attempt.mode == QuizMode.ranked
                        ? tokens.secondary
                        : tokens.primarySoft,
                  ),
                ],
              ),
              const SizedBox(height: MedRashSpace.sm),
              QuizProgressBar(progress: progress),
              const SizedBox(height: MedRashSpace.xl),
              Center(
                child: ArenaChip(
                  label: attempt.quiz.category,
                  color: tokens.primarySoft,
                ),
              ),
              const SizedBox(height: MedRashSpace.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final MediaQueryData mq = MediaQuery.of(context);
                  final bool landscape = mq.orientation == Orientation.landscape &&
                      constraints.maxWidth >= 600;

                  final Widget promptBlock = Text(
                    question.prompt,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                          height: 1.25,
                        ),
                    textAlign: landscape ? TextAlign.start : TextAlign.center,
                  );

                  final List<Widget> optionTiles = List<Widget>.generate(
                    question.options.length,
                    (int index) => Padding(
                      padding: const EdgeInsets.only(bottom: MedRashSpace.md),
                      child: _OptionTile(
                        letter: String.fromCharCode(65 + index),
                        text: question.options[index],
                        selected: _selectedIndex == index,
                        flash: _flash,
                        index: index,
                        onTap: () => _onSelectOption(index),
                      ),
                    ),
                  );

                  if (landscape) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: ArenaCard(
                            color: tokens.surface,
                            child: promptBlock,
                          ),
                        ),
                        const SizedBox(width: MedRashSpace.lg),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: optionTiles,
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ArenaCard(
                        color: tokens.surface,
                        padding: const EdgeInsets.all(MedRashSpace.lg),
                        child: promptBlock,
                      ),
                      const SizedBox(height: MedRashSpace.lg),
                      ...optionTiles,
                    ],
                  );
                },
              ),
              const SizedBox(height: MedRashSpace.lg),
              PressScale(
                enabled: _selectedIndex >= 0 && _flash == null,
                onTap: (_selectedIndex >= 0 && _flash == null)
                    ? _submitCurrentAnswer
                    : null,
                child: Opacity(
                  opacity: (_selectedIndex >= 0 && _flash == null) ? 1 : 0.55,
                  child: ArenaButton(
                    label: _flash == null
                        ? 'Submit Answer'
                        : (_flash!.isCorrect ? 'Correct!' : 'Keep going'),
                    icon: _flash == null
                        ? Icons.arrow_forward_rounded
                        : (_flash!.isCorrect
                            ? Icons.check_circle_rounded
                            : Icons.info_rounded),
                    backgroundColor: _flash == null
                        ? tokens.secondary
                        : (_flash!.isCorrect
                            ? tokens.successSurface
                            : tokens.dangerSurface),
                    foregroundColor: _flash == null
                        ? tokens.onSecondary
                        : (_flash!.isCorrect ? tokens.success : tokens.error),
                    onPressed: (_selectedIndex >= 0 && _flash == null)
                        ? _submitCurrentAnswer
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.selected,
    required this.flash,
    required this.index,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;
  final _AnswerFlash? flash;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool isFlashing = flash != null;
    final bool isCorrectOption = isFlashing && index == flash!.correctIndex;
    final bool isWrongSelected = isFlashing &&
        index == flash!.selectedIndex &&
        index != flash!.correctIndex;

    Color cardColor = tokens.surface;
    Color borderColor = tokens.outline;
    Color badgeBg = tokens.primarySoft;
    Color badgeFg = tokens.primaryStrong;
    Color textColor = tokens.textPrimary;
    FontWeight textWeight = FontWeight.w500;

    if (isCorrectOption) {
      cardColor = tokens.successSurface;
      borderColor = tokens.success;
      badgeBg = tokens.success;
      badgeFg = Colors.white;
      textWeight = FontWeight.w700;
    } else if (isWrongSelected) {
      cardColor = tokens.dangerSurface;
      borderColor = tokens.error;
      badgeBg = tokens.error;
      badgeFg = Colors.white;
      textWeight = FontWeight.w700;
    } else if (isFlashing) {
      // Other options dim slightly during flash to spotlight the truth.
      cardColor = tokens.surfaceMuted;
      textColor = tokens.textSecondary;
    } else if (selected) {
      cardColor = tokens.primarySoft;
      borderColor = tokens.primary;
      badgeBg = tokens.primary;
      badgeFg = Colors.white;
      textWeight = FontWeight.w700;
    }

    final bool reducedMotion = MediaQuery.of(context).disableAnimations;

    final Widget tile = AnimatedContainer(
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: borderColor, width: tokens.borderWidth),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            offset: Offset(tokens.shadowOffset, tokens.shadowOffset),
          ),
        ],
      ),
      padding: const EdgeInsets.all(MedRashSpace.md),
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
            ),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: TextStyle(
                color: badgeFg,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: MedRashSpace.md),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: textColor,
                    fontWeight: textWeight,
                  ),
            ),
          ),
          if (isCorrectOption)
            Icon(Icons.check_circle_rounded,
                color: tokens.success, size: MedRashIconSize.md)
          else if (isWrongSelected)
            Icon(Icons.cancel_rounded,
                color: tokens.error, size: MedRashIconSize.md),
        ],
      ),
    );

    return PressScale(
      enabled: !isFlashing,
      onTap: isFlashing ? null : onTap,
      child: tile,
    );
  }
}

class _ResumedBanner extends StatelessWidget {
  const _ResumedBanner({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: MedRashSpace.md),
      child: ArenaCard(
        color: tokens.primarySoft,
        padding: const EdgeInsets.all(MedRashSpace.md),
        child: Row(
          children: <Widget>[
            Icon(Icons.restart_alt_rounded, color: tokens.primaryStrong),
            const SizedBox(width: MedRashSpace.sm),
            Expanded(
              child: Text(
                'Resumed your attempt where you left off.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.primaryStrong,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            TextButton(
              onPressed: onRestart,
              child: Text(
                'Restart',
                style: TextStyle(
                  color: tokens.primaryStrong,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflinePracticeBanner extends StatelessWidget {
  const _OfflinePracticeBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: MedRashSpace.md),
      child: ArenaCard(
        color: tokens.warningSurface,
        padding: const EdgeInsets.all(MedRashSpace.md),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, color: tokens.onSecondary),
            const SizedBox(width: MedRashSpace.sm),
            Expanded(
              child: Text(
                'Offline practice \u2014 this attempt will NOT be recorded.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.onSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
