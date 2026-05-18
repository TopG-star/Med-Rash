import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/infra/auth_state_manager.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/repositories/profile_repository.dart';
import '../models/attempt.dart';
import '../models/question.dart';
import '../models/quiz.dart';
import 'quiz_repository.dart';

class NetlifySupabaseQuizRepository implements QuizRepository {
  NetlifySupabaseQuizRepository({
    required String functionsBaseUrl,
    required AuthStateManager authStateManager,
    required ProfileRepository profileRepository,
    http.Client? httpClient,
    String? gateApiKey,
  })  : _authStateManager = authStateManager,
        _profileRepository = profileRepository,
        _httpClient = httpClient ?? http.Client(),
        _gateApiKey = gateApiKey,
        _baseFunctionsUri = _normalizeFunctionsUri(functionsBaseUrl);

  InMemoryQuizRepository _delegate = InMemoryQuizRepository();
  bool _liveDataLoaded = false;
  final AuthStateManager _authStateManager;
  final ProfileRepository _profileRepository;
  final http.Client _httpClient;
  final String? _gateApiKey;
  final Uri _baseFunctionsUri;
  final Set<String> _serverBlockedRankedQuizIds = <String>{};

  static Uri _normalizeFunctionsUri(String raw) {
    final String normalized = raw.endsWith('/') ? raw : '$raw/';
    return Uri.parse(normalized);
  }

  Uri _functionUri(String functionName) {
    return _baseFunctionsUri.resolve(functionName);
  }

  Map<String, String> _buildHeaders() {
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
    };

    final String gateKey = _gateApiKey?.trim() ?? '';
    if (gateKey.isNotEmpty) {
      headers['x-medrash-gate-key'] = gateKey;
    }

    return headers;
  }

  Future<Map<String, dynamic>> _postJson(
    String functionName,
    Map<String, Object?> payload,
  ) async {
    final http.Response response = await _httpClient.post(
      _functionUri(functionName),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );

    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _GateHttpException(statusCode: response.statusCode, body: body);
    }

    return body;
  }

  Future<Map<String, Object?>> _buildIdentityPayload() async {
    final UserProfile? profile = await _profileRepository.getProfile();
    final String? participantId = _authStateManager.participantId;
    final String? deviceInstallId = _authStateManager.deviceId;

    if (participantId == null || participantId.isEmpty || deviceInstallId == null || deviceInstallId.isEmpty) {
      throw StateError('Identity spine is not initialized yet.');
    }

    return <String, Object?>{
      'participantId': participantId,
      'deviceInstallId': deviceInstallId,
      'profile': <String, Object?>{
        'fullName': profile?.fullName ?? 'Pilot Participant',
        'nickname': profile?.nickname ?? 'PilotUser',
        'facility': profile?.facility ?? 'Unknown Facility',
        'specialty': profile?.specialty ?? 'General',
      },
    };
  }

  Future<bool> _fetchRankedEligibility(String quizId) async {
    final Map<String, Object?> identityPayload = await _buildIdentityPayload();
    final Map<String, dynamic> response = await _postJson(
      'ranked-eligibility',
      <String, Object?>{
        ...identityPayload,
        'quizId': quizId,
      },
    );

    final Object? eligibleValue = response['eligible'];
    return eligibleValue is bool ? eligibleValue : false;
  }

  Future<void> _fetchAndSeedLiveData() async {
    if (_liveDataLoaded) return;
    if (_delegate.getActiveAttempt() != null) return;

    try {
      final Map<String, dynamic> response = await _postJson('quiz-list', <String, Object?>{});
      final Object? rawQuizzes = response['quizzes'];
      if (rawQuizzes is! List) return;

      final List<Quiz> quizzes = <Quiz>[];
      final Map<String, List<Question>> questionBank = <String, List<Question>>{};

      for (final Object? rawQuiz in rawQuizzes) {
        if (rawQuiz is! Map<String, dynamic>) continue;

        final String slug = (rawQuiz['slug'] as String? ?? '').trim();
        if (slug.isEmpty) continue;

        final Object? rawMeta = rawQuiz['metadata'];
        final Map<String, dynamic> meta =
            rawMeta is Map<String, dynamic> ? rawMeta : <String, dynamic>{};
        final String difficulty = (meta['difficulty'] as String? ?? 'Core').trim();
        final String durationLabel = (meta['duration_label'] as String? ?? '').trim();

        final Object? rawQs = rawQuiz['questions'];
        final List<dynamic> rawQuestions = rawQs is List ? rawQs : <dynamic>[];
        final int questionCount = rawQuestions.length;

        quizzes.add(
          Quiz(
            id: slug,
            title: (rawQuiz['title'] as String? ?? '').trim(),
            category: (rawQuiz['category'] as String? ?? '').trim(),
            product: (rawQuiz['product'] as String? ?? '').trim(),
            description: (rawQuiz['summary'] as String? ?? '').trim(),
            questionCount: questionCount,
            durationLabel:
                durationLabel.isNotEmpty ? durationLabel : _computeDurationLabel(questionCount),
            difficulty: difficulty,
          ),
        );

        final List<Question> questions = <Question>[];
        for (final Object? rawQ in rawQuestions) {
          if (rawQ is! Map<String, dynamic>) continue;

          final Object? rawOptions = rawQ['options'];
          final List<String> options = rawOptions is List
              ? rawOptions.map((Object? o) => o?.toString() ?? '').toList()
              : <String>[];

          questions.add(
            Question(
              id: rawQ['id'] as String?,
              prompt: (rawQ['prompt'] as String? ?? '').trim(),
              options: options,
              correctIndex: (rawQ['correct_index'] as int?) ?? 0,
              explanation: rawQ['explanation'] as String?,
            ),
          );
        }

        questionBank[slug] = questions;
      }

      if (quizzes.isNotEmpty) {
        _delegate = InMemoryQuizRepository.seeded(
          quizzes: quizzes,
          questionBank: questionBank,
        );
        _liveDataLoaded = true;
      }
    } catch (_) {
      // Network failure — fall back to InMemory stub.
      // The app remains functional; answer UUIDs will be absent from analytics.
    }
  }

  static String _computeDurationLabel(int questionCount) {
    final int minutes = (questionCount / 2.5).ceil();
    return '$minutes min';
  }

  Future<void> _submitAttemptToGate({
    required ActiveAttempt activeAttempt,
    required Attempt attempt,
    required List<QuestionReview> review,
  }) async {
    final Map<String, Object?> identityPayload = await _buildIdentityPayload();

    final String mode = activeAttempt.mode == QuizMode.ranked ? 'ranked' : 'learning';

    final List<Map<String, Object?>> answers = review
        .where(
          (QuestionReview r) => r.question.id != null && r.selectedIndex >= 0,
        )
        .map(
          (QuestionReview r) => <String, Object?>{
            'questionId': r.question.id!,
            'selectedIndex': r.selectedIndex,
            'selectedOptionText': r.question.options[r.selectedIndex],
            'isCorrect': r.isCorrect,
            'responseTimeMs': 0,
          },
        )
        .toList();

    await _postJson(
      'attempt-submit',
      <String, Object?>{
        ...identityPayload,
        'quizId': activeAttempt.quiz.id,
        'mode': mode,
        'score': attempt.score,
        'totalQuestions': attempt.totalQuestions,
        'timeTakenMs': _parseTimeLabelToMs(attempt.timeLabel),
        'origin': activeAttempt.origin == AttemptOrigin.qrSession
            ? 'qr_session'
            : 'open_access',
        'sessionId': activeAttempt.sessionId,
        'answers': answers,
      },
    );
  }

  int _parseTimeLabelToMs(String timeLabel) {
    final List<String> chunks = timeLabel.split(':');
    if (chunks.length != 2) {
      return 0;
    }

    final int minutes = int.tryParse(chunks[0]) ?? 0;
    final int seconds = int.tryParse(chunks[1]) ?? 0;
    return (minutes * 60 + seconds) * 1000;
  }

  @override
  Future<List<Quiz>> fetchActiveQuizzes() async {
    await _fetchAndSeedLiveData();
    return _delegate.fetchActiveQuizzes();
  }

  @override
  Future<Quiz> getQuizById(String quizId) {
    return _delegate.getQuizById(quizId);
  }

  @override
  bool canStartRankedAttempt(String quizId) {
    return _delegate.canStartRankedAttempt(quizId) && !_serverBlockedRankedQuizIds.contains(quizId);
  }

  @override
  Future<void> startAttempt({
    required String quizId,
    required QuizMode mode,
    AttemptOrigin origin = AttemptOrigin.openAccess,
    String? sessionId,
  }) async {
    if (mode == QuizMode.ranked) {
      if (!canStartRankedAttempt(quizId)) {
        throw StateError('Ranked attempt already used for this quiz.');
      }

      try {
        final bool isEligible = await _fetchRankedEligibility(quizId);
        if (!isEligible) {
          _serverBlockedRankedQuizIds.add(quizId);
          throw StateError('Ranked attempt already used for this quiz.');
        }
      } on _GateHttpException {
        throw StateError('Unable to verify ranked eligibility right now.');
      }
    }

    await _delegate.startAttempt(
      quizId: quizId,
      mode: mode,
      origin: origin,
      sessionId: sessionId,
    );
  }

  @override
  ActiveAttempt? getActiveAttempt() {
    return _delegate.getActiveAttempt();
  }

  @override
  Question? getCurrentQuestion() {
    return _delegate.getCurrentQuestion();
  }

  @override
  void selectAnswer(int answerIndex) {
    _delegate.selectAnswer(answerIndex);
  }

  @override
  bool canSubmitCurrentAnswer() {
    return _delegate.canSubmitCurrentAnswer();
  }

  @override
  Future<bool> submitCurrentAnswer() {
    return _delegate.submitCurrentAnswer();
  }

  @override
  Future<Attempt> finishAttempt() async {
    final ActiveAttempt? activeAttempt = _delegate.getActiveAttempt();
    final Attempt attempt = await _delegate.finishAttempt();
    final List<QuestionReview> review = _delegate.getLatestReview();

    if (activeAttempt == null) {
      return attempt;
    }

    try {
      await _submitAttemptToGate(
        activeAttempt: activeAttempt,
        attempt: attempt,
        review: review,
      );
      return attempt;
    } on _GateHttpException catch (error) {
      if (activeAttempt.mode == QuizMode.ranked &&
          error.statusCode == 409 &&
          error.body['code'] == 'RANKED_ATTEMPT_ALREADY_EXISTS') {
        _serverBlockedRankedQuizIds.add(activeAttempt.quiz.id);
        throw StateError('Ranked attempt already used for this quiz.');
      }

      throw StateError('Unable to submit attempt right now. Please retry shortly.');
    }
  }

  @override
  List<QuestionReview> getLatestReview() {
    return _delegate.getLatestReview();
  }
}

class _GateHttpException implements Exception {
  _GateHttpException({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final Map<String, dynamic> body;
}

