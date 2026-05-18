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

class _QuizRunnerPageState extends State<QuizRunnerPage> {
  late final QuizRepository _quizRepository;
  Future<void>? _futurePreparation;
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futurePreparation = _prepareAttempt();
  }

  Future<void> _prepareAttempt() async {
    if (_quizRepository.getActiveAttempt() != null) {
      return;
    }
    final List<Quiz> quizzes = await _quizRepository.fetchActiveQuizzes();
    await _quizRepository.startAttempt(
      quizId: quizzes.first.id,
      mode: QuizMode.learning,
    );
  }

  Future<void> _submitCurrentAnswer() async {
    if (_selectedIndex < 0) {
      return;
    }

    _quizRepository.selectAnswer(_selectedIndex);
    final bool isLastQuestion = await _quizRepository.submitCurrentAnswer();

    if (!mounted) {
      return;
    }

    if (isLastQuestion) {
      context.go('/result');
      return;
    }

    setState(() {
      _selectedIndex = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return ArenaScaffold(
      title: 'Quiz',
      showClose: true,
      child: FutureBuilder<void>(
        future: _futurePreparation,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final ActiveAttempt? attempt = _quizRepository.getActiveAttempt();
          final Question? question = _quizRepository.getCurrentQuestion();

          if (attempt == null || question == null) {
            return Center(
              child: ArenaButton(
                label: 'Back To Home',
                icon: Icons.home_outlined,
                onPressed: () => context.go('/home'),
              ),
            );
          }

          final double progress =
              (attempt.currentQuestionIndex + 1) / attempt.totalQuestions.toDouble();

          return ListView(
            children: <Widget>[
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
              ArenaCard(
                color: const Color(0xFFF8F8F8),
                child: Column(
                  children: <Widget>[
                    Text(
                      question.prompt,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ...List<Widget>.generate(question.options.length, (int index) {
                      final bool selected = _selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () => setState(() => _selectedIndex = index),
                          child: ArenaCard(
                            color: selected ? tokens.primary : tokens.surface,
                            child: Row(
                              children: <Widget>[
                                CircleAvatar(
                                  backgroundColor:
                                      selected ? tokens.textPrimary : tokens.surfaceMuted,
                                  child: Text(
                                    String.fromCharCode(65 + index),
                                    style: TextStyle(
                                      color: selected ? tokens.primary : tokens.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    question.options[index],
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ArenaButton(
                label: 'Submit Answer',
                icon: Icons.arrow_forward,
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