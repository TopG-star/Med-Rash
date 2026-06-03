import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/identity_badge.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/gradient_card.dart';
import '../../../core/ui/widgets/pill_segmented_control.dart';
import '../models/quiz.dart';
import '../repositories/quiz_repository.dart';

/// Browse-all quiz feed. Used both as the standalone Explore destination and
/// as the read-model for the Ranked/Learn tabs until those grow their own
/// filtering and badge UI.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

enum _ExploreTab { top, quiz, categories }

class _ExplorePageState extends State<ExplorePage> {
  late final QuizRepository _quizRepository;
  Future<List<Quiz>>? _futureQuizzes;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _ExploreTab _tab = _ExploreTab.top;

  @override
  void initState() {
    super.initState();
    _quizRepository = getIt<QuizRepository>();
    _futureQuizzes = _quizRepository.fetchActiveQuizzes();
    _searchController.addListener(() {
      final String next = _searchController.text.trim().toLowerCase();
      if (next != _query) {
        setState(() => _query = next);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaScaffold(
      title: MedRashStrings.exploreTitle,
      bottomNav: true,
      showBack: true,
      actions: const <Widget>[IdentityBadge()],
      child: MedRashConstrainedBody(
        maxWidth: 1080,
        child: FutureBuilder<List<Quiz>>(
          future: _futureQuizzes,
          builder:
              (BuildContext context, AsyncSnapshot<List<Quiz>> snapshot) {
            if (!snapshot.hasData) {
              return const MedRashSkeletonList(rowCount: 4);
            }

            final List<Quiz> quizzes = snapshot.data!;
            final List<Quiz> filtered = _applyFilter(quizzes, _query);

            return ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _SearchField(controller: _searchController),
                const SizedBox(height: MedRashSpace.md),
                PillSegmentedControl<_ExploreTab>(
                  value: _tab,
                  onChanged: (_ExploreTab v) => setState(() => _tab = v),
                  segments: const <PillSegment<_ExploreTab>>[
                    PillSegment<_ExploreTab>(
                        value: _ExploreTab.top, label: 'Top'),
                    PillSegment<_ExploreTab>(
                        value: _ExploreTab.quiz, label: 'Quiz'),
                    PillSegment<_ExploreTab>(
                        value: _ExploreTab.categories, label: 'Categories'),
                  ],
                ),
                const SizedBox(height: MedRashSpace.lg),
                if (filtered.isEmpty)
                  _EmptyResult(query: _query)
                else
                  ..._buildBody(context, tokens, filtered),
                const SizedBox(height: MedRashSpace.lg),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Quiz> _applyFilter(List<Quiz> quizzes, String query) {
    if (query.isEmpty) return quizzes;
    return quizzes
        .where((Quiz q) =>
            q.title.toLowerCase().contains(query) ||
            q.category.toLowerCase().contains(query) ||
            q.product.toLowerCase().contains(query))
        .toList(growable: false);
  }

  List<Widget> _buildBody(
    BuildContext context,
    ArenaDesignTokens tokens,
    List<Quiz> quizzes,
  ) {
    switch (_tab) {
      case _ExploreTab.top:
      case _ExploreTab.quiz:
        return <Widget>[
          for (final Quiz quiz in quizzes)
            Padding(
              padding: const EdgeInsets.only(bottom: MedRashSpace.md),
              child: _QuizCard(quiz: quiz),
            ),
        ];
      case _ExploreTab.categories:
        return _buildCategoryGroups(context, tokens, quizzes);
    }
  }

  List<Widget> _buildCategoryGroups(
    BuildContext context,
    ArenaDesignTokens tokens,
    List<Quiz> quizzes,
  ) {
    final Map<String, List<Quiz>> byCategory = <String, List<Quiz>>{};
    for (final Quiz q in quizzes) {
      byCategory.putIfAbsent(q.category, () => <Quiz>[]).add(q);
    }
    final List<String> categories = byCategory.keys.toList()..sort();
    final List<Widget> out = <Widget>[];
    for (final String cat in categories) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: MedRashSpace.sm),
        child: Text(
          cat,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
        ),
      ));
      for (final Quiz q in byCategory[cat]!) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: MedRashSpace.md),
          child: _QuizCard(quiz: q),
        ));
      }
    }
    return out;
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search quizzes, categories, products',
        prefixIcon: Icon(Icons.search_rounded, color: tokens.textSecondary),
        filled: true,
        fillColor: tokens.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: MedRashSpace.md, vertical: MedRashSpace.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: tokens.outlineMuted),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: tokens.outlineMuted),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: tokens.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({required this.quiz});

  final Quiz quiz;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color tint = _tintForProduct(tokens, quiz.product, quiz.category);
    return GradientCard(
      color: tokens.surface,
      borderColor: tokens.outlineMuted,
      padding: const EdgeInsets.all(MedRashSpace.sm),
      onTap: () => context.go('/quiz-detail', extra: quiz.id),
      child: Row(
        children: <Widget>[
          _QuizThumbnail(tint: tint, icon: _iconForCategory(quiz.category)),
          const SizedBox(width: MedRashSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  quiz.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${quiz.category} \u00b7 ${quiz.questionCount} Questions',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: MedRashSpace.sm),
          Icon(Icons.chevron_right_rounded, color: tokens.primary),
        ],
      ),
    );
  }
}

class _QuizThumbnail extends StatelessWidget {
  const _QuizThumbnail({required this.tint, required this.icon});

  final Color tint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.outlineMuted),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: tokens.textPrimary, size: MedRashIconSize.md),
    );
  }
}

/// Maps a quiz category to a representative glyph for the compact list
/// thumbnail. Falls back to a generic library icon so unknown categories
/// still render a recognisable tile.
IconData _iconForCategory(String category) {
  final String key = category.toLowerCase();
  if (key.contains('cardio') || key.contains('heart')) {
    return Icons.favorite_rounded;
  }
  if (key.contains('neuro') || key.contains('brain')) {
    return Icons.psychology_rounded;
  }
  if (key.contains('pharm') || key.contains('drug')) {
    return Icons.medication_rounded;
  }
  if (key.contains('onco') || key.contains('cancer')) {
    return Icons.biotech_rounded;
  }
  if (key.contains('derma') || key.contains('skin')) {
    return Icons.spa_rounded;
  }
  if (key.contains('respir') || key.contains('lung') || key.contains('pulm')) {
    return Icons.air_rounded;
  }
  if (key.contains('endo') || key.contains('diab')) {
    return Icons.bloodtype_rounded;
  }
  if (key.contains('pedia') || key.contains('child')) {
    return Icons.child_care_rounded;
  }
  return Icons.menu_book_rounded;
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String message = query.isEmpty
        ? 'No quizzes available yet.'
        : 'No quizzes match "$query".';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MedRashSpace.xl),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: tokens.textSecondary,
            ),
      ),
    );
  }
}

/// Maps a quiz's product / category to one of the four card tints so the
/// Explore feed reads as a multi-tone catalog rather than a wall of pink.
/// Pure function of the input strings -- deterministic so a given product
/// always lands on the same tint between sessions and devices.
Color _tintForProduct(
    ArenaDesignTokens tokens, String product, String category) {
  final String key = (product.isNotEmpty ? product : category).toLowerCase();
  if (key.isEmpty) return tokens.cardPeach;
  final List<Color> palette = <Color>[
    tokens.cardLavender,
    tokens.cardGold,
    tokens.cardMint,
    tokens.cardPeach,
  ];
  int hash = 0;
  for (int i = 0; i < key.length; i++) {
    hash = (hash * 31 + key.codeUnitAt(i)) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
