import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/repositories/profile_repository.dart';
import '../models/quiz.dart';
import '../repositories/quiz_repository.dart';

class QuizDetailPage extends StatefulWidget {
  const QuizDetailPage({
    super.key,
    this.quizId,
    this.preselectedMode,
  });

  final String? quizId;

  /// When non-null, the detail page hides the other-mode CTA and shows a
  /// mode-specific banner. Set by the Learn tab (Slice 2d) to commit the
  /// user to learning mode without showing the ranked button.
  final QuizMode? preselectedMode;

  @override
  State<QuizDetailPage> createState() => _QuizDetailPageState();
}

class _QuizDetailPageState extends State<QuizDetailPage> {
  late final QuizRepository _quizRepository;
  late final ProfileRepository _profileRepository;
  Future<Quiz>? _futureQuiz;
  Future<UserProfile?>? _futureProfile;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _profileRepository = getIt<ProfileRepository>();
    _futureQuiz = _loadQuiz();
    _futureProfile = _profileRepository.getProfile();
  }

  Future<Quiz> _loadQuiz() async {
    final List<Quiz> quizzes = await _quizRepository.fetchActiveQuizzes();
    final String quizId = widget.quizId ?? quizzes.first.id;
    return _quizRepository.getQuizById(quizId);
  }

  Future<void> _startMode(Quiz quiz, QuizMode mode) async {
    try {
      await _quizRepository.startAttempt(quizId: quiz.id, mode: mode);
      if (!mounted) {
        return;
      }
      context.go('/quiz');
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }
      final String message = error.message.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.isEmpty ? 'Unable to start attempt.' : message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'Quiz Detail',
      showBack: true,
      bottomNav: true,
      child: FutureBuilder<Quiz>(
        future: _futureQuiz,
        builder: (BuildContext context, AsyncSnapshot<Quiz> snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: MedRashSkeletonCard(),
            );
          }

          final Quiz quiz = snapshot.data!;
          final bool canStartRanked = _quizRepository.canStartRankedAttempt(quiz.id);
          final bool learnOnly = widget.preselectedMode == QuizMode.learning;
          final bool rankedOnly = widget.preselectedMode == QuizMode.ranked;

          final List<String> objectives = <String>[
            'Understand core ${quiz.category.toLowerCase()} decision points for ${quiz.product}.',
            'Identify common misconceptions from live and post-session engagement.',
            'Translate knowledge-gap analytics into targeted facility follow-up.',
          ];

          return ListView(
            children: <Widget>[
              if (learnOnly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ArenaCard(
                    color: context.arenaTokens.warningSurface,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.menu_book_rounded,
                          color: context.arenaTokens.outline,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            MedRashStrings.learnPreselectBanner,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              FutureBuilder<UserProfile?>(
                future: _futureProfile,
                builder: (BuildContext context, AsyncSnapshot<UserProfile?> profileSnap) {
                  final UserProfile? profile = profileSnap.data;
                  if (profile == null) {
                    return const SizedBox.shrink();
                  }
                  final tokens = context.arenaTokens;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ArenaCard(
                      color: tokens.warningSurface,
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.person_pin_rounded, color: tokens.outline),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Playing as @${profile.nickname} from ${profile.facility}.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ArenaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        ArenaChip(label: quiz.category),
                        const SizedBox(width: 8),
                        ArenaChip(label: quiz.product),
                        const Spacer(),
                        ArenaChip(label: quiz.durationLabel),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      quiz.title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      quiz.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(child: Text('${quiz.questionCount} Multiple Choice')),
                        Expanded(child: Text(quiz.difficulty)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('OBJECTIVES', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              ...objectives.map(
                (String objective) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ArenaCard(
                    child: Row(
                      children: <Widget>[
                        const CircleAvatar(child: Icon(Icons.check_rounded)),
                        const SizedBox(width: 16),
                        Expanded(child: Text(objective)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Show learning CTA whenever it's the preselected mode OR
              // whenever ranked is blocked — so a quiz reached via a
              // ranked-only entry point still offers a forward action when
              // the ranked attempt has been used. Prevents dead-end on
              // quiz-detail mirroring the SessionJoinPage Case B rule.
              if (!rankedOnly || !canStartRanked)
                PressScale(
                  onTap: () => _startMode(quiz, QuizMode.learning),
                  child: ArenaButton(
                    label: learnOnly
                        ? MedRashStrings.learnStartCta
                        : 'Start Learning',
                    icon: Icons.menu_book_rounded,
                    backgroundColor: learnOnly ? null : Colors.white,
                    onPressed: () => _startMode(quiz, QuizMode.learning),
                  ),
                ),
              if (!learnOnly) ...<Widget>[
                const SizedBox(height: 16),
                PressScale(
                  enabled: canStartRanked,
                  onTap:
                      canStartRanked ? () => _startMode(quiz, QuizMode.ranked) : null,
                  child: ArenaButton(
                    label: canStartRanked ? 'Go Ranked' : 'Ranked Attempt Used',
                    icon: Icons.workspace_premium_rounded,
                    onPressed: canStartRanked
                        ? () => _startMode(quiz, QuizMode.ranked)
                        : null,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}