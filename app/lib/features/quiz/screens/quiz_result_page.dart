import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
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

class _QuizResultPageState extends State<QuizResultPage> {
  late final QuizRepository _quizRepository;
  Future<Attempt>? _futureAttempt;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futureAttempt = _quizRepository.finishAttempt();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return ArenaScaffold(
      title: 'Quiz Result',
      showClose: true,
      child: FutureBuilder<Attempt>(
        future: _futureAttempt,
        builder: (BuildContext context, AsyncSnapshot<Attempt> snapshot) {
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
                      onPressed: () => context.go('/home'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final Attempt attempt = snapshot.data!;
          final List<QuestionReview> review = _quizRepository.getLatestReview();

          return ListView(
            children: <Widget>[
              ArenaCard(
                color: tokens.primary,
                child: Column(
                  children: <Widget>[
                    Text('GREAT EFFORT!', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 20),
                    Text('${attempt.score}/${attempt.totalQuestions}', style: Theme.of(context).textTheme.displayLarge),
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
                  final String correctOption = String.fromCharCode(65 + item.question.correctIndex);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ArenaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                item.isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
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
                          Text(item.question.prompt, style: Theme.of(context).textTheme.bodyLarge),
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
                onPressed: () => context.go('/home'),
              ),
              const SizedBox(height: 16),
              ArenaButton(
                label: 'View Leaderboard',
                icon: Icons.bar_chart,
                backgroundColor: tokens.secondary,
                onPressed: () => context.go('/leaderboard'),
              ),
            ],
          );
        },
      ),
    );
  }
}