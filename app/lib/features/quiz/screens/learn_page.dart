import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../models/quiz.dart';
import '../models/quiz_detail_launch.dart';
import '../repositories/quiz_repository.dart';

/// Learn tab. Lists active quizzes and routes taps into `/quiz-detail` with
/// `QuizMode.learning` preselected so the user lands on a learn-only CTA
/// instead of the dual ranked/learn choice (Slice 2d).
class LearnPage extends StatefulWidget {
  const LearnPage({super.key});

  @override
  State<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends State<LearnPage> {
  late final QuizRepository _quizRepository;
  Future<List<Quiz>>? _futureQuizzes;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futureQuizzes = _quizRepository.fetchActiveQuizzes();
  }

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: MedRashStrings.learnTitle,
      bottomNav: true,
      showBack: true,
      child: FutureBuilder<List<Quiz>>(
        future: _futureQuizzes,
        builder: (BuildContext context, AsyncSnapshot<List<Quiz>> snapshot) {
          if (!snapshot.hasData) {
            return const MedRashSkeletonList(rowCount: 4);
          }
          final List<Quiz> quizzes = snapshot.data!;
          return ListView(
            children: <Widget>[
              Text(
                MedRashStrings.learnIntro,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ...quizzes.map(
                (Quiz quiz) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () => context.go(
                      '/quiz-detail',
                      extra: QuizDetailLaunch(
                        quizId: quiz.id,
                        preselectedMode: QuizMode.learning,
                      ),
                    ),
                    child: ArenaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              ArenaChip(label: quiz.category),
                              const Spacer(),
                              Text(quiz.durationLabel),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            quiz.title,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('${quiz.questionCount} Questions \u2022 ${quiz.difficulty}'),
                        ],
                      ),
                    ),
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
