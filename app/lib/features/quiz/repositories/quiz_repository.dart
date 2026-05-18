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
    this.sessionId,
  });

  final Quiz quiz;
  final QuizMode mode;
  final AttemptOrigin origin;
  final int currentQuestionIndex;
  final int totalQuestions;
  final String? sessionId;
}

abstract class QuizRepository {
  Future<List<Quiz>> fetchActiveQuizzes();

  Future<Quiz> getQuizById(String quizId);

  bool canStartRankedAttempt(String quizId);

  Future<void> startAttempt({
    required String quizId,
    required QuizMode mode,
    AttemptOrigin origin = AttemptOrigin.openAccess,
    String? sessionId,
  });

  ActiveAttempt? getActiveAttempt();

  Question? getCurrentQuestion();

  void selectAnswer(int answerIndex);

  bool canSubmitCurrentAnswer();

  Future<bool> submitCurrentAnswer();

  Future<Attempt> finishAttempt();

  List<QuestionReview> getLatestReview();
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
  List<Question> _activeQuestions = <Question>[];
  int _currentQuestionIndex = 0;
  int _selectedAnswerIndex = -1;
  DateTime? _startedAt;
  final List<int> _submittedAnswers = <int>[];
  List<QuestionReview> _latestReview = <QuestionReview>[];
  final Set<String> _completedRankedQuizIds = <String>{};

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
  Future<void> startAttempt({
    required String quizId,
    required QuizMode mode,
    AttemptOrigin origin = AttemptOrigin.openAccess,
    String? sessionId,
  }) async {
    if (mode == QuizMode.ranked && !canStartRankedAttempt(quizId)) {
      throw StateError('Ranked attempt already used for this quiz.');
    }

    _activeQuiz = await getQuizById(quizId);
    _activeMode = mode;
    _activeOrigin = origin;
    _activeSessionId = sessionId?.trim().isEmpty ?? true ? null : sessionId?.trim();
    _activeQuestions = _questionBank[_activeQuiz!.id] ?? <Question>[];
    _currentQuestionIndex = 0;
    _selectedAnswerIndex = -1;
    _startedAt = DateTime.now();
    _submittedAnswers
      ..clear()
      ..addAll(List<int>.filled(_activeQuestions.length, -1));
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
    final int minutes = elapsed.inMinutes;
    final int seconds = elapsed.inSeconds % 60;
    final String timeLabel =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Attempt(
      score: score,
      totalQuestions: _activeQuestions.length,
      timeLabel: timeLabel,
      modeLabel: _activeMode == QuizMode.ranked ? 'Ranked' : 'Learning',
    );
  }

  @override
  List<QuestionReview> getLatestReview() {
    return _latestReview;
  }
}