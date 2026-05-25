import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../models/quiz.dart';
import '../repositories/quiz_repository.dart';
import '../storage/ranked_best_score_store.dart';
import '../../profile/widgets/complete_profile_banner.dart';

/// Ranked tab. Lists active quizzes and surfaces a gold/silver/bronze badge
/// on each row reflecting the local device's best ranked score (Slice 2c).
class RankedPage extends StatefulWidget {
  const RankedPage({super.key});

  @override
  State<RankedPage> createState() => _RankedPageState();
}

class _RankedPageState extends State<RankedPage> {
  late final QuizRepository _quizRepository;
  late final RankedBestScoreStore _bestScoreStore;
  StreamSubscription<void>? _bestScoreSub;
  Future<List<Quiz>>? _futureQuizzes;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _bestScoreStore = getIt<RankedBestScoreStore>();
    _futureQuizzes = _quizRepository.fetchActiveQuizzes();
    _bestScoreSub = _bestScoreStore.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _bestScoreSub?.cancel();
    super.dispose();
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
              const CompleteProfileBanner(),
              Text(
                MedRashStrings.rankedIntro,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ...quizzes.map((Quiz quiz) {
                final int? best = _bestScoreStore.bestPercentFor(quiz.id);
                final RankedTier tier =
                    best == null ? RankedTier.none : rankedTierFromPercent(best);
                return Padding(
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  quiz.title,
                                  style: Theme.of(context).textTheme.headlineMedium,
                                ),
                              ),
                              if (tier != RankedTier.none) ...<Widget>[
                                const SizedBox(width: 12),
                                _RankedTierBadge(tier: tier, percent: best!),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('${quiz.questionCount} Questions \u2022 ${quiz.difficulty}'),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _RankedTierBadge extends StatelessWidget {
  const _RankedTierBadge({required this.tier, required this.percent});

  final RankedTier tier;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final _BadgeStyle style = _styleFor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: style.border, width: tokens.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.workspace_premium, size: 16, color: style.foreground),
          const SizedBox(width: 6),
          Text(
            '${style.label} \u2022 $percent%',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: style.foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  _BadgeStyle _styleFor(RankedTier tier) {
    switch (tier) {
      case RankedTier.gold:
        return const _BadgeStyle(
          label: MedRashStrings.rankedTierGold,
          background: Color(0xFFFFF6D6),
          border: Color(0xFFE0B400),
          foreground: Color(0xFF7A5A00),
        );
      case RankedTier.silver:
        return const _BadgeStyle(
          label: MedRashStrings.rankedTierSilver,
          background: Color(0xFFEEF2F6),
          border: Color(0xFFB7C0CB),
          foreground: Color(0xFF4A5563),
        );
      case RankedTier.bronze:
        return const _BadgeStyle(
          label: MedRashStrings.rankedTierBronze,
          background: Color(0xFFF6E3D2),
          border: Color(0xFFC68754),
          foreground: Color(0xFF6E3B12),
        );
      case RankedTier.none:
        return const _BadgeStyle(
          label: '',
          background: Color(0x00000000),
          border: Color(0x00000000),
          foreground: Color(0xFF000000),
        );
    }
  }
}

class _BadgeStyle {
  const _BadgeStyle({
    required this.label,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color border;
  final Color foreground;
}
