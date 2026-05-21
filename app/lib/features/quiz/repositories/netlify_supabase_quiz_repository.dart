import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/infra/medrash_http_client.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/repositories/profile_repository.dart';
import '../models/attempt.dart';
import '../models/question.dart';
import '../models/quiz.dart';
import '../storage/quiz_attempt_store.dart';
import 'quiz_repository.dart';

/// HTTP gateway that wraps an [InMemoryQuizRepository] delegate.
///
/// Responsibilities layered on top of the delegate:
///   * Seed live quiz/question data from the Netlify `quiz-list` function so
///     submissions carry real Supabase question UUIDs.
///   * Persist in-progress attempts to [QuizAttemptStore] so a page refresh or
///     tab kill restores the user to the exact question with wall-clock-honest
///     timing.
///   * Persist a finalized snapshot so the /result page is idempotent on
///     refresh — no double POSTs.
///   * Enforce the "no recordable attempt without live data" rule: QR sessions
///     are refused if live data isn't ready; open-access learners may
///     explicitly opt-in to offline practice (which never POSTs).
class NetlifySupabaseQuizRepository implements QuizRepository {
  NetlifySupabaseQuizRepository({
    required MedRashHttpClient httpClient,
    required AuthStateManager authStateManager,
    required ProfileRepository profileRepository,
    required QuizAttemptStore store,
    required EventBus eventBus,
  })  : _authStateManager = authStateManager,
        _profileRepository = profileRepository,
        _store = store,
        _httpClient = httpClient,
        _eventBus = eventBus;

  InMemoryQuizRepository _delegate = InMemoryQuizRepository();
  final AuthStateManager _authStateManager;
  final ProfileRepository _profileRepository;
  final QuizAttemptStore _store;
  final MedRashHttpClient _httpClient;
  final EventBus _eventBus;
  final Set<String> _serverBlockedRankedQuizIds = <String>{};

  LiveDataStatus _liveDataStatus = LiveDataStatus.idle;
  Object? _lastSeedError;
  bool _initialized = false;
  Future<void>? _inflightInit;
  Future<void>? _inflightRetry;

  PersistedCompletedAttempt? _cachedCompleted;
  List<QuestionReview> _cachedCompletedReview = <QuestionReview>[];

  Future<Map<String, dynamic>> _postJson(
    String functionName,
    Map<String, Object?> payload,
  ) {
    return _httpClient.postJson(functionName, payload);
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

  Future<void> _seedFromGate() async {
    final Map<String, dynamic> response = await _postJson('quiz-list', <String, Object?>{});
    final Object? rawQuizzes = response['quizzes'];
    if (rawQuizzes is! List) {
      throw StateError('quiz-list response missing "quizzes" array.');
    }

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

    if (quizzes.isEmpty) {
      throw StateError('quiz-list returned zero quizzes.');
    }

    // Preserve any in-flight attempt on the existing delegate. If one exists,
    // the next seed will land after the attempt finishes.
    if (_delegate.getActiveAttempt() != null) {
      return;
    }

    _delegate = InMemoryQuizRepository.seeded(
      quizzes: quizzes,
      questionBank: questionBank,
    );
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
        'timeTakenMs': attempt.timeTakenMs,
        'origin': activeAttempt.origin == AttemptOrigin.qrSession
            ? 'qr_session'
            : 'open_access',
        'sessionId': activeAttempt.sessionId,
        'answers': answers,
      },
    );
  }

  // ---------------- Persistence helpers ----------------

  PersistedQuizSnapshot _snapshotQuiz(Quiz quiz) => PersistedQuizSnapshot(
        id: quiz.id,
        title: quiz.title,
        category: quiz.category,
        product: quiz.product,
        description: quiz.description,
        questionCount: quiz.questionCount,
        durationLabel: quiz.durationLabel,
        difficulty: quiz.difficulty,
      );

  List<PersistedQuestionSnapshot> _snapshotQuestions(List<Question> questions) {
    return questions
        .map(
          (Question q) => PersistedQuestionSnapshot(
            id: q.id,
            prompt: q.prompt,
            options: q.options,
            correctIndex: q.correctIndex,
            explanation: q.explanation,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _persistActive() async {
    final ActiveAttempt? active = _delegate.getActiveAttempt();
    if (active == null) {
      await _store.clearActive();
      return;
    }

    final List<Question> questions = _delegate.debugReadActiveQuestions();
    final List<int> submitted = _delegate.debugReadSubmittedAnswers(active.totalQuestions);

    final PersistedActiveAttempt persisted = PersistedActiveAttempt(
      quiz: _snapshotQuiz(active.quiz),
      questions: _snapshotQuestions(questions),
      modeName: active.mode == QuizMode.ranked ? 'ranked' : 'learning',
      originName: active.origin == AttemptOrigin.qrSession ? 'qrSession' : 'openAccess',
      sessionId: active.sessionId,
      startedAtMs: active.startedAt.millisecondsSinceEpoch,
      currentQuestionIndex: active.currentQuestionIndex,
      submittedAnswers: submitted,
      isOfflinePractice: active.isOfflinePractice,
    );

    await _store.saveActive(persisted);
  }

  // ---------------- QuizRepository contract ----------------

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    final Future<void>? inflight = _inflightInit;
    if (inflight != null) {
      return inflight;
    }
    final Future<void> task = _doInitialize();
    _inflightInit = task;
    try {
      await task;
    } finally {
      _inflightInit = null;
    }
  }

  Future<void> _doInitialize() async {
    // Load any cached completed snapshot first so /result is renderable even
    // if everything else fails.
    final PersistedCompletedAttempt? completed = _store.loadCompleted();
    if (completed != null) {
      _cachedCompleted = completed;
      _cachedCompletedReview = _materializeReviewFromSnapshot(completed);
    }

    // Best-effort live data seed.
    try {
      await ensureLiveDataReady();
    } catch (error) {
      developer.log(
        'live-data seed failed during initialize',
        name: 'NetlifySupabaseQuizRepository',
        error: error,
      );
    }

    // Restore in-flight attempt if any.
    final PersistedActiveAttempt? active = _store.loadActive();
    if (active != null) {
      await _restoreActive(active);
    }

    _initialized = true;

    // Best-effort auto-retry of any cached attempt left in pending/failed state.
    if (cachedCompletedNeedsSync) {
      unawaited(_autoRetryCachedAttempt());
    }
  }

  Future<void> _autoRetryCachedAttempt() async {
    try {
      await retrySyncCachedAttempt();
      developer.log(
        'auto-retry of cached attempt succeeded',
        name: 'NetlifySupabaseQuizRepository',
      );
    } catch (error, stack) {
      developer.log(
        'auto-retry of cached attempt failed; will surface manual retry on /result',
        name: 'NetlifySupabaseQuizRepository',
        error: error,
        stackTrace: stack,
      );
    }
  }

  List<QuestionReview> _materializeReviewFromSnapshot(PersistedCompletedAttempt snapshot) {
    return snapshot.review
        .map(
          (PersistedQuestionReview r) => QuestionReview(
            question: Question(
              id: r.questionId,
              prompt: r.prompt,
              options: r.options,
              correctIndex: r.correctIndex,
              explanation: r.explanation,
            ),
            selectedIndex: r.selectedIndex,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _restoreActive(PersistedActiveAttempt persisted) async {
    if (persisted.questions.isEmpty) {
      await _store.clearActive();
      return;
    }

    final Quiz quiz = Quiz(
      id: persisted.quiz.id,
      title: persisted.quiz.title,
      category: persisted.quiz.category,
      product: persisted.quiz.product,
      description: persisted.quiz.description,
      questionCount: persisted.quiz.questionCount,
      durationLabel: persisted.quiz.durationLabel,
      difficulty: persisted.quiz.difficulty,
    );

    final List<Question> questions = persisted.questions
        .map(
          (PersistedQuestionSnapshot q) => Question(
            id: q.id,
            prompt: q.prompt,
            options: q.options,
            correctIndex: q.correctIndex,
            explanation: q.explanation,
          ),
        )
        .toList(growable: false);

    final QuizMode mode = persisted.modeName == 'ranked' ? QuizMode.ranked : QuizMode.learning;
    final AttemptOrigin origin =
        persisted.originName == 'qrSession' ? AttemptOrigin.qrSession : AttemptOrigin.openAccess;

    _delegate.restoreActiveAttempt(
      quiz: quiz,
      mode: mode,
      origin: origin,
      sessionId: persisted.sessionId,
      questions: questions,
      startedAt: DateTime.fromMillisecondsSinceEpoch(persisted.startedAtMs),
      submittedAnswers: persisted.submittedAnswers,
      currentQuestionIndex: persisted.currentQuestionIndex,
      isOfflinePractice: persisted.isOfflinePractice,
    );
  }

  @override
  LiveDataStatus get liveDataStatus => _liveDataStatus;

  @override
  Object? get lastSeedError => _lastSeedError;

  @override
  Future<void> ensureLiveDataReady({bool force = false}) async {
    if (_liveDataStatus == LiveDataStatus.ready && !force) return;
    _liveDataStatus = LiveDataStatus.loading;
    _lastSeedError = null;
    try {
      await _seedFromGate();
      _liveDataStatus = LiveDataStatus.ready;
    } catch (error, stack) {
      _liveDataStatus = LiveDataStatus.failed;
      _lastSeedError = error;
      developer.log(
        'live-data seed failed',
        name: 'NetlifySupabaseQuizRepository',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  Future<List<Quiz>> fetchActiveQuizzes() async {
    if (_liveDataStatus != LiveDataStatus.ready) {
      try {
        await ensureLiveDataReady();
      } catch (error, stack) {
        developer.log(
          'live-data seed unavailable; falling back to stub list',
          name: 'NetlifySupabaseQuizRepository',
          error: error,
          stackTrace: stack,
        );
        // Quiz discovery still works on the stub list. Recordable submissions
        // are gated separately in startAttempt.
      }
    }
    return _delegate.fetchActiveQuizzes();
  }

  @override
  Future<Quiz> getQuizById(String quizId) {
    return _delegate.getQuizById(quizId);
  }

  @override
  bool canStartRankedAttempt(String quizId) {
    return _delegate.canStartRankedAttempt(quizId) &&
        !_serverBlockedRankedQuizIds.contains(quizId);
  }

  @override
  Future<void> startAttempt({
    required String quizId,
    required QuizMode mode,
    AttemptOrigin origin = AttemptOrigin.openAccess,
    String? sessionId,
    bool allowOfflinePractice = false,
  }) async {
    // QR sessions are recordable-or-nothing.
    if (origin == AttemptOrigin.qrSession) {
      if (_liveDataStatus != LiveDataStatus.ready) {
        await ensureLiveDataReady();
      }
    } else if (_liveDataStatus != LiveDataStatus.ready && !allowOfflinePractice) {
      // Open-access learners need live data unless they opted into offline.
      await ensureLiveDataReady();
    }

    if (mode == QuizMode.ranked) {
      if (allowOfflinePractice) {
        throw StateError('Ranked attempts cannot run in offline practice mode.');
      }
      if (!canStartRankedAttempt(quizId)) {
        throw StateError('Ranked attempt already used for this quiz.');
      }
      try {
        final bool isEligible = await _fetchRankedEligibility(quizId);
        if (!isEligible) {
          _serverBlockedRankedQuizIds.add(quizId);
          throw StateError('Ranked attempt already used for this quiz.');
        }
      } on MedRashGateException {
        throw StateError('Unable to verify ranked eligibility right now.');
      }
    }

    await _delegate.startAttempt(
      quizId: quizId,
      mode: mode,
      origin: origin,
      sessionId: sessionId,
      allowOfflinePractice: allowOfflinePractice,
    );
    await _persistActive();
  }

  @override
  Future<void> restartActiveAttempt() async {
    await _delegate.restartActiveAttempt();
    await _persistActive();
  }

  @override
  Future<void> clearActiveAttempt() async {
    await _delegate.clearActiveAttempt();
    await _store.clearActive();
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
  Future<bool> submitCurrentAnswer() async {
    final bool finished = await _delegate.submitCurrentAnswer();
    await _persistActive();
    return finished;
  }

  @override
  Future<Attempt> finishAttempt() async {
    final ActiveAttempt? activeAttempt = _delegate.getActiveAttempt();

    if (activeAttempt == null) {
      final PersistedCompletedAttempt? cached = _cachedCompleted;
      if (cached != null) {
        return _attemptFromSnapshot(cached);
      }
      return const Attempt(
        score: 0,
        totalQuestions: 0,
        timeLabel: '00:00',
        modeLabel: 'Learning',
        timeTakenMs: 0,
      );
    }

    final Attempt attempt = await _delegate.finishAttempt();
    final List<QuestionReview> review = _delegate.getLatestReview();

    // Persist the completed snapshot BEFORE POST so a refresh mid-POST still
    // renders the result page idempotently.
    final PersistedCompletedAttempt baseSnapshot = PersistedCompletedAttempt(
      quizId: activeAttempt.quiz.id,
      modeName: activeAttempt.mode == QuizMode.ranked ? 'ranked' : 'learning',
      originName: activeAttempt.origin == AttemptOrigin.qrSession ? 'qrSession' : 'openAccess',
      sessionId: activeAttempt.sessionId,
      score: attempt.score,
      totalQuestions: attempt.totalQuestions,
      timeTakenMs: attempt.timeTakenMs,
      completedAtMs: DateTime.now().millisecondsSinceEpoch,
      review: review
          .map(
            (QuestionReview r) => PersistedQuestionReview(
              questionId: r.question.id,
              prompt: r.question.prompt,
              options: r.question.options,
              correctIndex: r.question.correctIndex,
              explanation: r.question.explanation,
              selectedIndex: r.selectedIndex,
            ),
          )
          .toList(growable: false),
      isOfflinePractice: activeAttempt.isOfflinePractice,
      syncStatus: activeAttempt.isOfflinePractice ? 'skipped_offline' : 'pending',
    );

    await _store.saveCompleted(baseSnapshot);
    _cachedCompleted = baseSnapshot;
    _cachedCompletedReview = List<QuestionReview>.unmodifiable(review);

    if (activeAttempt.isOfflinePractice) {
      await _store.clearActive();
      return attempt;
    }

    try {
      await _submitAttemptToGate(
        activeAttempt: activeAttempt,
        attempt: attempt,
        review: review,
      );
      final PersistedCompletedAttempt synced =
          baseSnapshot.copyWith(syncStatus: 'synced', syncError: null);
      await _store.saveCompleted(synced);
      _cachedCompleted = synced;
      await _store.clearActive();
      _emitAttemptSubmitted(synced);
      return attempt;
    } on MedRashGateException catch (error) {
      if (activeAttempt.mode == QuizMode.ranked &&
          error.statusCode == 409 &&
          error.code == 'RANKED_ATTEMPT_ALREADY_EXISTS') {
        _serverBlockedRankedQuizIds.add(activeAttempt.quiz.id);
        final PersistedCompletedAttempt synced =
            baseSnapshot.copyWith(syncStatus: 'synced', syncError: null);
        await _store.saveCompleted(synced);
        _cachedCompleted = synced;
        await _store.clearActive();
        throw StateError('Ranked attempt already used for this quiz.');
      }

      final PersistedCompletedAttempt failed = baseSnapshot.copyWith(
        syncStatus: 'failed',
        syncError: 'HTTP ${error.statusCode}',
      );
      await _store.saveCompleted(failed);
      _cachedCompleted = failed;
      await _store.clearActive();
      throw StateError('Unable to submit attempt right now. Please retry shortly.');
    } catch (error) {
      final PersistedCompletedAttempt failed = baseSnapshot.copyWith(
        syncStatus: 'failed',
        syncError: error.toString(),
      );
      await _store.saveCompleted(failed);
      _cachedCompleted = failed;
      await _store.clearActive();
      rethrow;
    }
  }

  Attempt _attemptFromSnapshot(PersistedCompletedAttempt snapshot) {
    final int totalSeconds = (snapshot.timeTakenMs ~/ 1000).clamp(0, 1 << 31);
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final String timeLabel =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return Attempt(
      score: snapshot.score,
      totalQuestions: snapshot.totalQuestions,
      timeLabel: timeLabel,
      modeLabel: snapshot.modeName == 'ranked' ? 'Ranked' : 'Learning',
      timeTakenMs: snapshot.timeTakenMs,
    );
  }

  @override
  List<QuestionReview> getLatestReview() {
    final List<QuestionReview> delegateReview = _delegate.getLatestReview();
    if (delegateReview.isNotEmpty) return delegateReview;
    return _cachedCompletedReview;
  }

  @override
  Attempt? getCachedCompletedAttempt() {
    final PersistedCompletedAttempt? cached = _cachedCompleted;
    if (cached == null) return null;
    return _attemptFromSnapshot(cached);
  }

  @override
  List<QuestionReview> getCachedCompletedReview() => _cachedCompletedReview;

  @override
  bool get cachedCompletedNeedsSync {
    final PersistedCompletedAttempt? cached = _cachedCompleted;
    if (cached == null) return false;
    return cached.syncStatus == 'failed' || cached.syncStatus == 'pending';
  }

  @override
  Future<void> retrySyncCachedAttempt() async {
    final Future<void>? inflight = _inflightRetry;
    if (inflight != null) return inflight;
    final Future<void> task = _doRetrySyncCachedAttempt();
    _inflightRetry = task;
    try {
      await task;
    } finally {
      _inflightRetry = null;
    }
  }

  Future<void> _doRetrySyncCachedAttempt() async {
    final PersistedCompletedAttempt? cached = _cachedCompleted;
    if (cached == null) {
      throw StateError('No completed attempt to sync.');
    }
    if (cached.syncStatus == 'synced' || cached.syncStatus == 'skipped_offline') {
      return;
    }

    if (_liveDataStatus != LiveDataStatus.ready) {
      await ensureLiveDataReady();
    }

    final Map<String, Object?> identityPayload = await _buildIdentityPayload();
    final List<Map<String, Object?>> answers = cached.review
        .where(
          (PersistedQuestionReview r) =>
              r.questionId != null && r.questionId!.isNotEmpty && r.selectedIndex >= 0,
        )
        .map(
          (PersistedQuestionReview r) => <String, Object?>{
            'questionId': r.questionId!,
            'selectedIndex': r.selectedIndex,
            'selectedOptionText':
                r.selectedIndex < r.options.length ? r.options[r.selectedIndex] : '',
            'isCorrect': r.selectedIndex == r.correctIndex,
            'responseTimeMs': 0,
          },
        )
        .toList();

    try {
      await _postJson(
        'attempt-submit',
        <String, Object?>{
          ...identityPayload,
          'quizId': cached.quizId,
          'mode': cached.modeName,
          'score': cached.score,
          'totalQuestions': cached.totalQuestions,
          'timeTakenMs': cached.timeTakenMs,
          'origin': cached.originName == 'qrSession' ? 'qr_session' : 'open_access',
          'sessionId': cached.sessionId,
          'answers': answers,
        },
      );
      final PersistedCompletedAttempt synced =
          cached.copyWith(syncStatus: 'synced', syncError: null);
      await _store.saveCompleted(synced);
      _cachedCompleted = synced;
      _emitAttemptSubmitted(synced);
    } on MedRashGateException catch (error) {
      final PersistedCompletedAttempt failed = cached.copyWith(
        syncStatus: 'failed',
        syncError: 'HTTP ${error.statusCode}',
      );
      await _store.saveCompleted(failed);
      _cachedCompleted = failed;
      rethrow;
    }
  }

  @override
  Future<void> clearCachedCompletedAttempt() async {
    _cachedCompleted = null;
    _cachedCompletedReview = <QuestionReview>[];
    await _store.clearCompleted();
    await _delegate.clearCachedCompletedAttempt();
  }

  void _emitAttemptSubmitted(PersistedCompletedAttempt snapshot) {
    _eventBus.emit(
      AttemptSubmittedEvent(
        quizId: snapshot.quizId,
        mode: snapshot.modeName,
        origin: snapshot.originName == 'qrSession' ? 'qr_session' : 'open_access',
        score: snapshot.score,
        totalQuestions: snapshot.totalQuestions,
        sessionId: snapshot.sessionId,
      ),
    );
  }
}

