import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal serialized snapshot of a Question — enough to restore a quiz attempt
/// without needing to re-fetch live data.
class PersistedQuestionSnapshot {
  const PersistedQuestionSnapshot({
    required this.id,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String? id;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? explanation;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'prompt': prompt,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
      };

  static PersistedQuestionSnapshot? fromJson(Map<String, Object?> j) {
    try {
      final List<dynamic> rawOptions = j['options'] as List<dynamic>;
      return PersistedQuestionSnapshot(
        id: j['id'] as String?,
        prompt: j['prompt'] as String,
        options: rawOptions.map((dynamic e) => e.toString()).toList(growable: false),
        correctIndex: (j['correctIndex'] as num).toInt(),
        explanation: j['explanation'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Serialized Quiz header for resume.
class PersistedQuizSnapshot {
  const PersistedQuizSnapshot({
    required this.id,
    required this.title,
    required this.category,
    required this.product,
    required this.description,
    required this.questionCount,
    required this.durationLabel,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String category;
  final String product;
  final String description;
  final int questionCount;
  final String durationLabel;
  final String difficulty;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'category': category,
        'product': product,
        'description': description,
        'questionCount': questionCount,
        'durationLabel': durationLabel,
        'difficulty': difficulty,
      };

  static PersistedQuizSnapshot? fromJson(Map<String, Object?> j) {
    try {
      return PersistedQuizSnapshot(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        category: (j['category'] as String?) ?? '',
        product: (j['product'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        questionCount: (j['questionCount'] as num?)?.toInt() ?? 0,
        durationLabel: (j['durationLabel'] as String?) ?? '',
        difficulty: (j['difficulty'] as String?) ?? 'Core',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Snapshot of an in-progress quiz attempt that survives page refresh / tab kill.
class PersistedActiveAttempt {
  const PersistedActiveAttempt({
    required this.quiz,
    required this.questions,
    required this.modeName,
    required this.originName,
    required this.sessionId,
    required this.startedAtMs,
    required this.currentQuestionIndex,
    required this.submittedAnswers,
    required this.isOfflinePractice,
  });

  final PersistedQuizSnapshot quiz;
  final List<PersistedQuestionSnapshot> questions;
  final String modeName; // 'learning' | 'ranked'
  final String originName; // 'openAccess' | 'qrSession'
  final String? sessionId;
  final int startedAtMs; // epoch millis
  final int currentQuestionIndex;
  final List<int> submittedAnswers;
  final bool isOfflinePractice;

  String get quizId => quiz.id;

  Map<String, Object?> toJson() => <String, Object?>{
        'quiz': quiz.toJson(),
        'questions':
            questions.map((PersistedQuestionSnapshot q) => q.toJson()).toList(growable: false),
        'modeName': modeName,
        'originName': originName,
        'sessionId': sessionId,
        'startedAtMs': startedAtMs,
        'currentQuestionIndex': currentQuestionIndex,
        'submittedAnswers': submittedAnswers,
        'isOfflinePractice': isOfflinePractice,
      };

  static PersistedActiveAttempt? fromJson(Map<String, Object?> j) {
    try {
      final Object? rawQuiz = j['quiz'];
      if (rawQuiz is! Map) return null;
      final PersistedQuizSnapshot? quiz =
          PersistedQuizSnapshot.fromJson(rawQuiz.cast<String, Object?>());
      if (quiz == null) return null;

      final List<dynamic> rawQuestions = (j['questions'] as List<dynamic>?) ?? <dynamic>[];
      final List<PersistedQuestionSnapshot> questions = <PersistedQuestionSnapshot>[];
      for (final dynamic entry in rawQuestions) {
        if (entry is Map) {
          final PersistedQuestionSnapshot? parsed =
              PersistedQuestionSnapshot.fromJson(entry.cast<String, Object?>());
          if (parsed != null) questions.add(parsed);
        }
      }

      final List<dynamic> rawAnswers = (j['submittedAnswers'] as List<dynamic>?) ?? <dynamic>[];

      return PersistedActiveAttempt(
        quiz: quiz,
        questions: questions,
        modeName: j['modeName'] as String,
        originName: j['originName'] as String,
        sessionId: j['sessionId'] as String?,
        startedAtMs: (j['startedAtMs'] as num).toInt(),
        currentQuestionIndex: (j['currentQuestionIndex'] as num).toInt(),
        submittedAnswers:
            rawAnswers.map((dynamic e) => (e as num).toInt()).toList(growable: false),
        isOfflinePractice: (j['isOfflinePractice'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One question's serialized review entry (what user picked, the correct answer, etc.).
class PersistedQuestionReview {
  const PersistedQuestionReview({
    required this.questionId,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.selectedIndex,
  });

  final String? questionId;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
  final int selectedIndex;

  Map<String, Object?> toJson() => <String, Object?>{
        'questionId': questionId,
        'prompt': prompt,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
        'selectedIndex': selectedIndex,
      };

  static PersistedQuestionReview? fromJson(Map<String, Object?> j) {
    try {
      final List<dynamic> rawOptions = j['options'] as List<dynamic>;
      return PersistedQuestionReview(
        questionId: j['questionId'] as String?,
        prompt: j['prompt'] as String,
        options: rawOptions.map((dynamic e) => e.toString()).toList(growable: false),
        correctIndex: (j['correctIndex'] as num).toInt(),
        explanation: j['explanation'] as String?,
        selectedIndex: (j['selectedIndex'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Finalized attempt snapshot — re-rendered on /result page refresh without re-POSTing.
class PersistedCompletedAttempt {
  const PersistedCompletedAttempt({
    required this.quizId,
    required this.modeName,
    required this.originName,
    required this.sessionId,
    required this.score,
    required this.totalQuestions,
    required this.timeTakenMs,
    required this.completedAtMs,
    required this.review,
    required this.isOfflinePractice,
    required this.syncStatus,
    this.syncError,
  });

  final String quizId;
  final String modeName;
  final String originName;
  final String? sessionId;
  final int score;
  final int totalQuestions;
  final int timeTakenMs;
  final int completedAtMs;
  final List<PersistedQuestionReview> review;
  final bool isOfflinePractice;
  final String syncStatus; // 'synced' | 'pending' | 'failed' | 'skipped_offline'
  final String? syncError;

  PersistedCompletedAttempt copyWith({String? syncStatus, String? syncError}) {
    return PersistedCompletedAttempt(
      quizId: quizId,
      modeName: modeName,
      originName: originName,
      sessionId: sessionId,
      score: score,
      totalQuestions: totalQuestions,
      timeTakenMs: timeTakenMs,
      completedAtMs: completedAtMs,
      review: review,
      isOfflinePractice: isOfflinePractice,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: syncError ?? this.syncError,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'quizId': quizId,
        'modeName': modeName,
        'originName': originName,
        'sessionId': sessionId,
        'score': score,
        'totalQuestions': totalQuestions,
        'timeTakenMs': timeTakenMs,
        'completedAtMs': completedAtMs,
        'review': review.map((PersistedQuestionReview r) => r.toJson()).toList(growable: false),
        'isOfflinePractice': isOfflinePractice,
        'syncStatus': syncStatus,
        'syncError': syncError,
      };

  static PersistedCompletedAttempt? fromJson(Map<String, Object?> j) {
    try {
      final List<dynamic> rawReview = j['review'] as List<dynamic>;
      final List<PersistedQuestionReview> review = <PersistedQuestionReview>[];
      for (final dynamic entry in rawReview) {
        if (entry is Map<String, Object?>) {
          final PersistedQuestionReview? parsed = PersistedQuestionReview.fromJson(entry);
          if (parsed != null) review.add(parsed);
        } else if (entry is Map) {
          final PersistedQuestionReview? parsed =
              PersistedQuestionReview.fromJson(entry.cast<String, Object?>());
          if (parsed != null) review.add(parsed);
        }
      }
      return PersistedCompletedAttempt(
        quizId: j['quizId'] as String,
        modeName: j['modeName'] as String,
        originName: j['originName'] as String,
        sessionId: j['sessionId'] as String?,
        score: (j['score'] as num).toInt(),
        totalQuestions: (j['totalQuestions'] as num).toInt(),
        timeTakenMs: (j['timeTakenMs'] as num).toInt(),
        completedAtMs: (j['completedAtMs'] as num).toInt(),
        review: review,
        isOfflinePractice: (j['isOfflinePractice'] as bool?) ?? false,
        syncStatus: (j['syncStatus'] as String?) ?? 'synced',
        syncError: j['syncError'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class QuizAttemptStore {
  QuizAttemptStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _activeKey = 'medrash.attempt.active.v1';
  static const String _completedKey = 'medrash.attempt.completed.v1';

  Future<void> saveActive(PersistedActiveAttempt value) async {
    await _prefs.setString(_activeKey, jsonEncode(value.toJson()));
  }

  PersistedActiveAttempt? loadActive() {
    final String? raw = _prefs.getString(_activeKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return PersistedActiveAttempt.fromJson(decoded);
      }
      if (decoded is Map) {
        return PersistedActiveAttempt.fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      // Corrupt entry — drop it so it never blocks future attempts.
      _prefs.remove(_activeKey);
    }
    return null;
  }

  Future<void> clearActive() async {
    await _prefs.remove(_activeKey);
  }

  Future<void> saveCompleted(PersistedCompletedAttempt value) async {
    await _prefs.setString(_completedKey, jsonEncode(value.toJson()));
  }

  PersistedCompletedAttempt? loadCompleted() {
    final String? raw = _prefs.getString(_completedKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return PersistedCompletedAttempt.fromJson(decoded);
      }
      if (decoded is Map) {
        return PersistedCompletedAttempt.fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      _prefs.remove(_completedKey);
    }
    return null;
  }

  Future<void> clearCompleted() async {
    await _prefs.remove(_completedKey);
  }
}
