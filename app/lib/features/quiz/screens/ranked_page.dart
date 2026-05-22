import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../models/quiz.dart';
import '../repositories/quiz_repository.dart';

/// Ranked tab introduced in Slice 2a. For now it lists all active quizzes;
/// Slice 2c adds completion-tier badges (gold/silver/bronze) driven by the
/// local ranked-best-score store.
class RankedPage extends StatefulWidget {
  const RankedPage({super.key});

  @override
  State<RankedPage> createState() => _RankedPageState();
}

class _RankedPageState extends State<RankedPage> {
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
      title: MedRashStrings.rankedTitle,
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
                MedRashStrings.rankedIntro,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ...quizzes.map(
                (Quiz quiz) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () => context.go('/quiz-detail', extra: quiz.id),
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
