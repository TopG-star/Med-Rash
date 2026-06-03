import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../models/participant_stats.dart';

/// P8.c — donut + per-category bar chart rendered on the Profile / Stats
/// tab. Self-contained (no external chart dependency) so the pilot can
/// ship without bumping `pubspec.yaml`. Renders skeleton/empty/loaded
/// states from a single [ParticipantStats] input.
class StatsCharts extends StatelessWidget {
  const StatsCharts({super.key, required this.stats, this.isLoading = false});

  final ParticipantStats stats;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _StatsSkeleton();
    }
    final bool isEmpty =
        stats.monthlyAttempts == 0 && stats.accuracyByCategory.isEmpty;
    if (isEmpty) {
      return const _StatsEmpty();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MonthlyDonutCard(
          attempts: stats.monthlyAttempts,
          target: stats.monthlyTarget,
          progress: stats.monthlyProgress,
        ),
        const SizedBox(height: MedRashSpace.lg),
        _AccuracyBarsCard(rows: stats.accuracyByCategory),
      ],
    );
  }
}

class _MonthlyDonutCard extends StatelessWidget {
  const _MonthlyDonutCard({
    required this.attempts,
    required this.target,
    required this.progress,
  });

  final int attempts;
  final int target;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final TextStyle? headlineBase =
        Theme.of(context).textTheme.titleLarge?.copyWith(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
              height: 1.25,
            );
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text.rich(
            TextSpan(
              style: headlineBase,
              children: <InlineSpan>[
                const TextSpan(text: 'You have played a total '),
                TextSpan(
                  text:
                      '$attempts ${attempts == 1 ? 'quiz' : 'quizzes'}',
                  style: headlineBase?.copyWith(color: tokens.primary),
                ),
                const TextSpan(text: ' this month!'),
              ],
            ),
          ),
          const SizedBox(height: MedRashSpace.md),
          Text(
            'MONTHLY RANKED ATTEMPTS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: MedRashSpace.md),
          Row(
            children: <Widget>[
              SizedBox(
                width: 132,
                height: 132,
                child: CustomPaint(
                  painter: _DonutPainter(
                    progress: progress,
                    trackColor: tokens.surfaceMuted,
                    fillColor: tokens.primary,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '$attempts',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w800,
                                color: tokens.textPrimary,
                              ),
                        ),
                        Text(
                          'of $target',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: MedRashSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${(progress * 100).round()}% of monthly target',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      attempts >= target
                          ? 'Target hit \u2014 nice work. Keep stacking ranked reps.'
                          : 'Finish ${target - attempts} more ranked attempts to hit your monthly target.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.width * 0.13;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width - stroke) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress > 0) {
      final Paint fill = Paint()
        ..color = fillColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _AccuracyBarsCard extends StatelessWidget {
  const _AccuracyBarsCard({required this.rows});

  final List<CategoryAccuracy> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    if (rows.isEmpty) {
      return ArenaCard(
        padding: const EdgeInsets.all(MedRashSpace.xl),
        child: Text(
          'No per-category accuracy yet \u2014 finish a few ranked quizzes to light up this chart.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                height: 1.4,
              ),
        ),
      );
    }
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'ACCURACY BY CATEGORY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: MedRashSpace.md),
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: MedRashSpace.md),
            _AccuracyBar(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _AccuracyBar extends StatelessWidget {
  const _AccuracyBar({required this.row});

  final CategoryAccuracy row;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final double clamped = (row.accuracyPct.clamp(0, 100)) / 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                row.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
              ),
            ),
            Text(
              '${row.accuracyPct}%',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    color: tokens.primary,
                  ),
            ),
            const SizedBox(width: 6),
            Text(
              '\u00b7 ${row.attempts}\u00d7',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: <Widget>[
              Container(
                height: 10,
                color: tokens.surfaceMuted,
              ),
              FractionallySizedBox(
                widthFactor: clamped,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[tokens.primary, tokens.secondary],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.xl),
      child: Row(
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: tokens.surfaceMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: MedRashSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 14,
                  width: 160,
                  color: tokens.surfaceMuted,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: double.infinity,
                  color: tokens.surfaceMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsEmpty extends StatelessWidget {
  const _StatsEmpty();

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.insights_rounded,
                color: tokens.primary,
                size: MedRashIconSize.lg,
              ),
              const SizedBox(width: MedRashSpace.md),
              Expanded(
                child: Text(
                  'No ranked attempts yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.md),
          Text(
            'Finish your first ranked quiz to light up the monthly donut and per-category accuracy bars.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}
