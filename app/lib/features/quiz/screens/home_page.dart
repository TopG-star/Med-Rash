import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../models/quiz.dart';
import '../repositories/quiz_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
      title: 'MedRash',
      bottomNav: true,
      child: FutureBuilder<List<Quiz>>(
        future: _futureQuizzes,
        builder: (BuildContext context, AsyncSnapshot<List<Quiz>> snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<Quiz> quizzes = snapshot.data!;

          return ListView(
            children: <Widget>[
              Text(
                'Pick a topic and keep it under three minutes.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ...quizzes.map(
                (Quiz quiz) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: InkWell(
                    onTap: () => context.go('/academy', extra: quiz.id),
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
                          const SizedBox(height: 8),
                          Text('Product: ${quiz.product}'),
                          const SizedBox(height: 20),
                          Text(quiz.title, style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 12),
                          Text(quiz.description),
                          const SizedBox(height: 20),
                          Row(
                            children: <Widget>[
                              Expanded(child: Text('${quiz.questionCount} Questions')),
                              Expanded(child: Text(quiz.difficulty)),
                            ],
                          ),
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
