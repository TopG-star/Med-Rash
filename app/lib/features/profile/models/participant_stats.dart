/// P8.c — payload returned by the `participant-stats` Netlify function.
/// Currently scoped to the current calendar month; the `period` field on
/// the request side is reserved for future weekly/yearly expansions.
class ParticipantStats {
  const ParticipantStats({
    required this.monthlyAttempts,
    required this.monthlyTarget,
    required this.accuracyByCategory,
  });

  /// Total ranked attempts the participant has completed since the start
  /// of the current calendar month (UTC).
  final int monthlyAttempts;

  /// Pilot target the donut chart fills toward. Server-supplied so it
  /// can be tuned without a client rebuild.
  final int monthlyTarget;

  /// Per-category accuracy breakdown for the bar chart. Sorted by attempt
  /// count descending and capped server-side; pilot returns at most six
  /// rows so the chart stays legible.
  final List<CategoryAccuracy> accuracyByCategory;

  static const ParticipantStats empty = ParticipantStats(
    monthlyAttempts: 0,
    monthlyTarget: 20,
    accuracyByCategory: <CategoryAccuracy>[],
  );

  factory ParticipantStats.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = json['accuracyByCategory'] is List
        ? json['accuracyByCategory'] as List<dynamic>
        : const <dynamic>[];
    return ParticipantStats(
      monthlyAttempts: _readInt(json['monthlyAttempts']),
      monthlyTarget: _readInt(json['monthlyTarget'], fallback: 20),
      accuracyByCategory: raw
          .whereType<Map<String, dynamic>>()
          .map(CategoryAccuracy.fromJson)
          .toList(growable: false),
    );
  }

  /// Progress toward the monthly target, clamped to [0, 1] so the donut
  /// renderer never has to defend against bad inputs.
  double get monthlyProgress {
    if (monthlyTarget <= 0) return 0;
    final double v = monthlyAttempts / monthlyTarget;
    if (v.isNaN || v.isInfinite) return 0;
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
  }
}

class CategoryAccuracy {
  const CategoryAccuracy({
    required this.category,
    required this.accuracyPct,
    required this.attempts,
  });

  final String category;

  /// 0..100 integer percentage of correct answers across attempts in
  /// this category.
  final int accuracyPct;

  /// Number of attempts the percentile was derived from. Used by the
  /// chart to surface a small "Nx" hint next to each bar.
  final int attempts;

  factory CategoryAccuracy.fromJson(Map<String, dynamic> json) {
    return CategoryAccuracy(
      category: (json['category'] ?? '').toString(),
      accuracyPct: _readInt(json['accuracyPct']),
      attempts: _readInt(json['attempts']),
    );
  }
}

int _readInt(Object? v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}
