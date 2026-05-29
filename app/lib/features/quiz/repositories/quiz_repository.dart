import '../models/attempt.dart';
import '../models/question.dart';
import '../models/quiz.dart';

enum QuizMode {
  learning,
  ranked,
}

enum AttemptOrigin {
  openAccess,
  qrSession,
}

/// State of the live-data seed (quiz-list fetch).
/// `ready` means the question bank in this repository carries real Supabase
/// UUIDs and submissions will be recorded. Anything else means submissions are
/// either blocked (qrSession) or relegated to opt-in offline practice.
enum LiveDataStatus { idle, loading, ready, failed }

class QuestionReview {
  const QuestionReview({
    required this.question,
    required this.selectedIndex,
  });

  final Question question;
  final int selectedIndex;

  bool get isCorrect => selectedIndex == question.correctIndex;
}

class ActiveAttempt {
  const ActiveAttempt({
    required this.quiz,
    required this.mode,
    required this.origin,
    required this.currentQuestionIndex,
    required this.totalQuestions,
    required this.startedAt,
    required this.isOfflinePractice,
    required this.isResumed,
    this.sessionId,
  });

  final Quiz quiz;
  final QuizMode mode;
  final AttemptOrigin origin;
  final int currentQuestionIndex;
  final int totalQuestions;
  final DateTime startedAt;
  final bool isOfflinePractice;
  final bool isResumed;
  final String? sessionId;
}

abstract class QuizRepository {
  /// Hydrate any persisted state from disk and prime live data. Idempotent.
  Future<void> initialize();

  /// Synchronous status of the live-data seed (quiz-list).
  LiveDataStatus get liveDataStatus;

  /// Last error from a failed seed, if any.
  Object? get lastSeedError;

  /// Force-refresh live data. Throws on failure.
  Future<void> ensureLiveDataReady({bool force = false});

  Future<List<Quiz>> fetchActiveQuizzes();

  Future<Quiz> getQuizById(String quizId);

  bool canStartRankedAttempt(String quizId);

  /// Best-effort eligibility preflight. Updates the repository's local
  /// blocked set so a follow-up [canStartRankedAttempt] reflects authoritative
  /// server state. MUST NOT throw — network/transport failures are swallowed
  /// and the caller falls back to tap-time eligibility checks inside
  /// [startAttempt]. Implementations that have no server-side state (the
  /// in-memory fake) treat this as a no-op.
  Future<void> prefetchRankedEligibility(String quizId);

  /// Start a recordable attempt. Throws StateError if live data isn't ready
  /// and `allowOfflinePractice` is false.
  Future<void> startAttempt({
    required String quizId,
    required QuizMode mode,
    AttemptOrigin origin = AttemptOrigin.openAccess,
    String? sessionId,
    bool allowOfflinePractice = false,
  });

  /// Discard any in-flight attempt and start fresh with the same parameters.
  Future<void> restartActiveAttempt();

  /// Clear any in-flight attempt without starting a new one.
  Future<void> clearActiveAttempt();

  ActiveAttempt? getActiveAttempt();

  Question? getCurrentQuestion();

  void selectAnswer(int answerIndex);

  bool canSubmitCurrentAnswer();

  Future<bool> submitCurrentAnswer();

  /// Finalize the active attempt: compute score, persist a completed snapshot,
  /// clear active state, then attempt to sync to the backend (no-op for
  /// offline practice). Throws on sync failure but the snapshot is preserved.
  Future<Attempt> finishAttempt();

  List<QuestionReview> getLatestReview();

  /// Cached result from the last finalize, if any (survives page refresh).
  Attempt? getCachedCompletedAttempt();

  /// Review for the cached completed attempt.
  List<QuestionReview> getCachedCompletedReview();

  /// True if the cached completed attempt was never successfully synced.
  bool get cachedCompletedNeedsSync;

  /// Re-attempt to sync the cached completed attempt to the backend.
  Future<void> retrySyncCachedAttempt();

  /// Drop the cached completed snapshot (e.g. after user dismisses /result).
  Future<void> clearCachedCompletedAttempt();
}

class InMemoryQuizRepository implements QuizRepository {
  InMemoryQuizRepository()
      : _quizzes = _defaultQuizzes,
        _questionBank = _defaultQuestionBank;

  /// Creates a repository pre-seeded with live data fetched from the backend.
  /// Used by [NetlifySupabaseQuizRepository] once the quiz-list gate function
  /// has returned questions with their Supabase UUIDs.
  InMemoryQuizRepository.seeded({
    required List<Quiz> quizzes,
    required Map<String, List<Question>> questionBank,
  })  : _quizzes = quizzes,
        _questionBank = questionBank;

  final List<Quiz> _quizzes;
  final Map<String, List<Question>> _questionBank;

  static const List<Quiz> _defaultQuizzes = <Quiz>[
    Quiz(
      id: 'tavanic-infection-stewardship',
      title: 'Tavanic In UTI And Respiratory Infections',
      category: 'UTI/Infections',
      product: 'Tavanic',
      description: 'Master class knowledge check for guideline-aligned anti-infective use.',
      questionCount: 5,
      durationLabel: '2 min',
      difficulty: 'Core',
    ),
    Quiz(
      id: 'clexane-vte-masterclass',
      title: 'Clexane In VTE: DVT And PE Management',
      category: 'VTE',
      product: 'Clexane',
      description: 'Roundtable-ready assessment on risk stratification and anticoagulation pathways.',
      questionCount: 5,
      durationLabel: '2 min',
      difficulty: 'Core',
    ),
    Quiz(
      id: 'lantus-basal-diabetes-care',
      title: 'Lantus In Diabetes Basal Control',
      category: 'Diabetes',
      product: 'Lantus',
      description: 'CME module focused on basal insulin initiation and titration safety.',
      questionCount: 5,
      durationLabel: '2 min',
      difficulty: 'Core',
    ),
  ];

  static const Map<String, List<Question>> _defaultQuestionBank = <String, List<Question>>{
    'tavanic-infection-stewardship': <Question>[
      Question(
        prompt: 'In complicated UTI with high resistance risk, what is the key first action before finalizing empirical therapy?',
        options: <String>[
          'Collect urine culture and local susceptibility context',
          'Start long-term steroid cover',
          'Delay all treatment for 72 hours',
          'Use broad therapy without reassessment',
        ],
        correctIndex: 0,
        explanation: 'Culture-informed decisions and local resistance patterns reduce inappropriate use and improve outcomes.',
      ),
      Question(
        prompt: 'Which stewardship action best supports preserving fluoroquinolone effectiveness in practice?',
        options: <String>[
          'Use only when clinical indication and guideline context align',
          'Prescribe for all low-risk viral symptoms',
          'Avoid documenting indication in notes',
          'Skip follow-up once symptoms improve',
        ],
        correctIndex: 0,
        explanation: 'Clear indication, documentation, and follow-up are central to antimicrobial stewardship.',
      ),
      Question(
        prompt: 'During a post-CME audit, which metric most directly signals a product knowledge gap?',
        options: <String>[
          'Most-missed question clusters by facility and specialty',
          'Only the number of slide views',
          'The color theme used in presentation',
          'Average meeting duration alone',
        ],
        correctIndex: 0,
        explanation: 'Missed-question clusters reveal specific knowledge deficiencies tied to audience segments.',
      ),
      Question(
        prompt: 'For live QR and post-session retries, what analytics pairing is most useful to management?',
        options: <String>[
          'First-attempt accuracy versus learning-retry improvement',
          'Phone brand versus battery level',
          'Session poster color versus attendance',
          'Presenter shirt color versus score',
        ],
        correctIndex: 0,
        explanation: 'Comparing first and retry performance quantifies learning lift after field engagement.',
      ),
      Question(
        prompt: 'Which region-level signal best identifies where awareness reinforcement is needed first?',
        options: <String>[
          'Lowest completion-adjusted score by disease area',
          'Highest number of parking slots at facilities',
          'Largest conference room in the region',
          'Most social media followers of staff',
        ],
        correctIndex: 0,
        explanation: 'Completion-adjusted regional scores avoid bias from low participation and better target interventions.',
      ),
    ],
    'clexane-vte-masterclass': <Question>[
      Question(
        prompt: 'Which patient profile should trigger immediate VTE risk re-evaluation during a hospital round?',
        options: <String>[
          'Reduced mobility with new unilateral leg swelling',
          'Mild seasonal rhinitis only',
          'Stable vision without pain',
          'Isolated dry skin complaint',
        ],
        correctIndex: 0,
        explanation: 'Immobility and unilateral swelling are high-priority flags in DVT risk assessment.',
      ),
      Question(
        prompt: 'In pilot analytics, what indicates meaningful post-roundtable learning in VTE topics?',
        options: <String>[
          'Reduced repeat errors on risk-stratification questions',
          'More selfies taken at the venue',
          'Higher coffee consumption',
          'Longer introductions by host',
        ],
        correctIndex: 0,
        explanation: 'Lower repeat errors on the same concepts demonstrates retained understanding.',
      ),
      Question(
        prompt: 'Which audience segmentation is most useful for targeted follow-up detailing?',
        options: <String>[
          'Facility type, specialty mix, and profession role',
          'Preferred pen color of participants',
          'Seat number in meeting room',
          'Order of arrival only',
        ],
        correctIndex: 0,
        explanation: 'Follow-up quality improves when insights map directly to care context and role responsibilities.',
      ),
      Question(
        prompt: 'What is the best interpretation if participation is high but completion is low?',
        options: <String>[
          'Onboarding worked, but quiz experience or timing needs optimization',
          'No interest in topic at all',
          'Data capture should be disabled',
          'Leaderboard should be removed immediately',
        ],
        correctIndex: 0,
        explanation: 'High starts with low finishes usually points to UX, session pacing, or question length issues.',
      ),
      Question(
        prompt: 'Which management view best supports resource allocation for future VTE education?',
        options: <String>[
          'Region and facility heatmap of awareness gaps',
          'List of random participant nicknames only',
          'Session title alphabetical order',
          'Average projector brightness',
        ],
        correctIndex: 0,
        explanation: 'Heatmaps make gap concentration obvious and actionable for planning next interventions.',
      ),
    ],
    'lantus-basal-diabetes-care': <Question>[
      Question(
        prompt: 'In basal insulin education, which outcome best reflects practical understanding after CME?',
        options: <String>[
          'Correct titration decision in case-based questions',
          'Memorizing product logo details',
          'Reciting event agenda from memory',
          'Remembering meeting snack options',
        ],
        correctIndex: 0,
        explanation: 'Case-based titration decisions reflect applied clinical understanding.',
      ),
      Question(
        prompt: 'What is the strongest pilot indicator of behavior-oriented learning retention?',
        options: <String>[
          'Improved retry scores with lower completion time',
          'More profile picture updates',
          'Higher Wi-Fi signal strength',
          'Longer question stems',
        ],
        correctIndex: 0,
        explanation: 'Faster, more accurate retries suggest concepts are being internalized.',
      ),
      Question(
        prompt: 'Which dataset is most useful for identifying diabetes-topic misconceptions by cadre?',
        options: <String>[
          'Answer-level incorrect patterns by role and specialty',
          'Only total attendance counts',
          'Only number of sessions run',
          'Only nickname edit frequency',
        ],
        correctIndex: 0,
        explanation: 'Answer-level analysis reveals exactly where each cadre struggles.',
      ),
      Question(
        prompt: 'If one region has low awareness and low activity, what is the best next action?',
        options: <String>[
          'Schedule targeted session and monitor completion lift',
          'Ignore the region until quarter-end',
          'Disable leaderboard globally',
          'Pause all quizzes in other regions',
        ],
        correctIndex: 0,
        explanation: 'Focused intervention plus measurable lift tracking is the strongest response pattern.',
      ),
      Question(
        prompt: 'Which KPI pairing should be reviewed together for fair performance interpretation?',
        options: <String>[
          'Completion rate and score distribution by quiz mode',
          'Host name and background music style',
          'Phone model and wallpaper image',
          'Slide count and venue AC temperature',
        ],
        correctIndex: 0,
        explanation: 'Completion and score distribution together prevent misleading single-metric conclusions.',
      ),
    ],
  };

  Quiz? _activeQuiz;
  QuizMode _activeMode = QuizMode.learning;
  AttemptOrigin _activeOrigin = AttemptOrigin.openAccess;
  String? _activeSessionId;
  bool _activeIsOfflinePractice = false;
  bool _activeIsResumed = false;
  List<Question> _activeQuestions = <Question>[];
  int _currentQuestionIndex = 0;
  int _selectedAnswerIndex = -1;
  DateTime? _startedAt;
  final List<int> _submittedAnswers = <int>[];
  List<QuestionReview> _latestReview = <QuestionReview>[];
  final Set<String> _completedRankedQuizIds = <String>{};
  Attempt? _cachedCompletedAttempt;
  List<QuestionReview> _cachedCompletedReview = <QuestionReview>[];

  @override
  Future<void> initialize() async {}

  @override
  LiveDataStatus get liveDataStatus => LiveDataStatus.ready;

  @override
  Object? get lastSeedError => null;

  @override
  Future<void> ensureLiveDataReady({bool force = false}) async {}

  @override
  Future<List<Quiz>> fetchActiveQuizzes() async {
    return _quizzes;
  }

  @override
  Future<Quiz> getQuizById(String quizId) async {
    return _quizzes.firstWhere(
      (Quiz quiz) => quiz.id == quizId,
      orElse: () => _quizzes.first,
    );
  }

  @override
  bool canStartRankedAttempt(String quizId) {
    return !_completedRankedQuizIds.contains(quizId);
  }

  @override
  Future<void> prefetchRankedEligibility(String quizId) async {
    // In-memory repo has no server-side state; eligibility is fully captured
    // by [_completedRankedQuizIds] which mutates synchronously inside
    // [startAttempt]. Nothing to prefetch.
  }

  @override
  Future<void> startAttempt({
    required String quizId,
    required QuizMode mode,
    AttemptOrigin origin = AttemptOrigin.openAccess,
    String? sessionId,
    bool allowOfflinePractice = false,
  }) async {
    if (mode == QuizMode.ranked && !canStartRankedAttempt(quizId)) {
      throw StateError('Ranked attempt already used for this quiz.');
    }

    _activeQuiz = await getQuizById(quizId);
    _activeMode = mode;
    _activeOrigin = origin;
    _activeSessionId = (sessionId == null || sessionId.trim().isEmpty) ? null : sessionId.trim();
    _activeIsOfflinePractice = allowOfflinePractice;
    _activeIsResumed = false;
    _activeQuestions = _questionBank[_activeQuiz!.id] ?? <Question>[];
    _currentQuestionIndex = 0;
    _selectedAnswerIndex = -1;
    _startedAt = DateTime.now();
    _submittedAnswers
      ..clear()
      ..addAll(List<int>.filled(_activeQuestions.length, -1));
  }

  /// Re-hydrate an in-progress attempt from a persisted snapshot. Used by the
  /// Netlify wrapper after a page refresh.
  void restoreActiveAttempt({
    required Quiz quiz,
    required QuizMode mode,
    required AttemptOrigin origin,
    String? sessionId,
    required List<Question> questions,
    required DateTime startedAt,
    required List<int> submittedAnswers,
    required int currentQuestionIndex,
    required bool isOfflinePractice,
  }) {
    _activeQuiz = quiz;
    _activeMode = mode;
    _activeOrigin = origin;
    _activeSessionId = sessionId;
    _activeIsOfflinePractice = isOfflinePractice;
    _activeIsResumed = true;
    _activeQuestions = questions;
    _startedAt = startedAt;
    _selectedAnswerIndex = -1;
    _submittedAnswers
      ..clear()
      ..addAll(submittedAnswers);
    // Defensive padding if persisted list is shorter than the current bank.
    while (_submittedAnswers.length < questions.length) {
      _submittedAnswers.add(-1);
    }
    _currentQuestionIndex = currentQuestionIndex.clamp(0, questions.isEmpty ? 0 : questions.length - 1);
  }

  @override
  Future<void> restartActiveAttempt() async {
    final Quiz? quiz = _activeQuiz;
    if (quiz == null) {
      return;
    }
    final QuizMode mode = _activeMode;
    final AttemptOrigin origin = _activeOrigin;
    final String? sessionId = _activeSessionId;
    final bool offline = _activeIsOfflinePractice;
    await clearActiveAttempt();
    await startAttempt(
      quizId: quiz.id,
      mode: mode,
      origin: origin,
      sessionId: sessionId,
      allowOfflinePractice: offline,
    );
  }

  @override
  Future<void> clearActiveAttempt() async {
    _activeQuiz = null;
    _activeQuestions = <Question>[];
    _submittedAnswers.clear();
    _currentQuestionIndex = 0;
    _selectedAnswerIndex = -1;
    _startedAt = null;
    _activeSessionId = null;
    _activeIsOfflinePractice = false;
    _activeIsResumed = false;
  }

  /// Internal accessor for the wrapper repository — returns a defensive copy
  /// of the current active questions list.
  List<Question> debugReadActiveQuestions() {
    return List<Question>.unmodifiable(_activeQuestions);
  }

  /// Internal accessor for the wrapper repository — returns a defensive copy
  /// of submitted-answer indices, padded with -1 to [totalQuestions].
  List<int> debugReadSubmittedAnswers(int totalQuestions) {
    final List<int> copy = List<int>.from(_submittedAnswers);
    while (copy.length < totalQuestions) {
      copy.add(-1);
    }
    return List<int>.unmodifiable(copy);
  }

  @override
  ActiveAttempt? getActiveAttempt() {
    final Quiz? activeQuiz = _activeQuiz;
    if (activeQuiz == null || _activeQuestions.isEmpty) {
      return null;
    }

    return ActiveAttempt(
      quiz: activeQuiz,
      mode: _activeMode,
      origin: _activeOrigin,
      currentQuestionIndex: _currentQuestionIndex,
      totalQuestions: _activeQuestions.length,
      startedAt: _startedAt ?? DateTime.now(),
      isOfflinePractice: _activeIsOfflinePractice,
      isResumed: _activeIsResumed,
      sessionId: _activeSessionId,
    );
  }

  @override
  Question? getCurrentQuestion() {
    if (_activeQuestions.isEmpty || _currentQuestionIndex >= _activeQuestions.length) {
      return null;
    }
    return _activeQuestions[_currentQuestionIndex];
  }

  @override
  void selectAnswer(int answerIndex) {
    _selectedAnswerIndex = answerIndex;
  }

  @override
  bool canSubmitCurrentAnswer() {
    return _selectedAnswerIndex >= 0;
  }

  @override
  Future<bool> submitCurrentAnswer() async {
    if (!canSubmitCurrentAnswer() || _activeQuestions.isEmpty) {
      return false;
    }

    _submittedAnswers[_currentQuestionIndex] = _selectedAnswerIndex;
    _selectedAnswerIndex = -1;

    final bool isLastQuestion = _currentQuestionIndex == _activeQuestions.length - 1;
    if (!isLastQuestion) {
      _currentQuestionIndex += 1;
    }

    return isLastQuestion;
  }

  @override
  Future<Attempt> finishAttempt() async {
    if (_activeQuestions.isEmpty) {
      return const Attempt(
        score: 0,
        totalQuestions: 0,
        timeLabel: '00:00',
        modeLabel: 'Learning',
        timeTakenMs: 0,
      );
    }

    int score = 0;
    final List<QuestionReview> review = <QuestionReview>[];

    for (int i = 0; i < _activeQuestions.length; i++) {
      final Question question = _activeQuestions[i];
      final int selectedIndex = _submittedAnswers[i];
      if (selectedIndex == question.correctIndex) {
        score += 1;
      }
      review.add(
        QuestionReview(
          question: question,
          selectedIndex: selectedIndex,
        ),
      );
    }

    _latestReview = review;

    if (_activeMode == QuizMode.ranked && _activeQuiz != null) {
      _completedRankedQuizIds.add(_activeQuiz!.id);
    }

    final DateTime startedAt = _startedAt ?? DateTime.now();
    final Duration elapsed = DateTime.now().difference(startedAt);
    final int totalSeconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final String timeLabel =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    final Attempt attempt = Attempt(
      score: score,
      totalQuestions: _activeQuestions.length,
      timeLabel: timeLabel,
      modeLabel: _activeMode == QuizMode.ranked ? 'Ranked' : 'Learning',
      timeTakenMs: elapsed.inMilliseconds < 0 ? 0 : elapsed.inMilliseconds,
    );

    _cachedCompletedAttempt = attempt;
    _cachedCompletedReview = List<QuestionReview>.unmodifiable(review);

    return attempt;
  }

  @override
  List<QuestionReview> getLatestReview() {
    return _latestReview;
  }

  @override
  Attempt? getCachedCompletedAttempt() => _cachedCompletedAttempt;

  @override
  List<QuestionReview> getCachedCompletedReview() => _cachedCompletedReview;

  @override
  bool get cachedCompletedNeedsSync => false;

  @override
  Future<void> retrySyncCachedAttempt() async {}

  @override
  Future<void> clearCachedCompletedAttempt() async {
    _cachedCompletedAttempt = null;
    _cachedCompletedReview = <QuestionReview>[];
  }
}