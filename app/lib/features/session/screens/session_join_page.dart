import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../quiz/repositories/quiz_repository.dart';
import '../events/last_session_recorded_event.dart';
import '../models/session_info.dart';
import '../repositories/session_repository.dart';
import '../storage/last_session_store.dart';

class SessionJoinPage extends StatefulWidget {
  const SessionJoinPage({super.key, this.joinCode});

  final String? joinCode;

  @override
  State<SessionJoinPage> createState() => _SessionJoinPageState();
}

class _SessionJoinPageState extends State<SessionJoinPage> {
  late final SessionRepository _sessionRepository;
  late final QuizRepository _quizRepository;
  late final LastSessionStore _lastSessionStore;
  late final EventBus _eventBus;
  Future<SessionInfo>? _futureSession;

  @override
  void initState() {
    super.initState();
    _sessionRepository = getIt<SessionRepository>();
    _quizRepository = getIt<QuizRepository>();
    _lastSessionStore = getIt<LastSessionStore>();
    _eventBus = getIt<EventBus>();
    _futureSession = _loadSession();
  }

  Future<SessionInfo> _loadSession() async {
    final String joinCode = widget.joinCode?.trim() ?? '';
    final SessionInfo session = joinCode.isNotEmpty
        ? await _sessionRepository.resolveSessionByJoinCode(joinCode)
        : await _sessionRepository.getFeaturedSession();
    // Persist whatever join code the resolved session reports (preferred) so
    // the home screen can offer a Continue card. Fall back to the inbound
    // path param if the repository didn't surface one (e.g. featured-session
    // fallback).
    final String? recordedCode = session.joinCode?.trim().isNotEmpty == true
        ? session.joinCode!.trim()
        : (joinCode.isNotEmpty ? joinCode : null);
    if (recordedCode != null) {
      await _lastSessionStore.record(recordedCode);
      _eventBus.emit(LastSessionRecordedEvent(joinCode: recordedCode));
    }
    return session;
  }

  Future<void> _startMode(SessionInfo session, QuizMode mode) async {
    try {
      await _quizRepository.startAttempt(
        quizId: session.quizId,
        mode: mode,
        origin: AttemptOrigin.qrSession,
        sessionId: session.sessionId,
      );
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
      title: 'Join Session',
      showBack: true,
      child: FutureBuilder<SessionInfo>(
        future: _futureSession,
        builder: (BuildContext context, AsyncSnapshot<SessionInfo> snapshot) {
          if (snapshot.hasError) {
            final String message = snapshot.error is StateError
                ? (snapshot.error as StateError).message.toString()
                : 'Unable to load session right now.';

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(message),
                  const SizedBox(height: 12),
                  ArenaButton(
                    label: 'Retry',
                    icon: Icons.refresh,
                    onPressed: () {
                      setState(() {
                        _futureSession = _loadSession();
                      });
                    },
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final SessionInfo session = snapshot.data!;
          final bool canStartRanked = _quizRepository.canStartRankedAttempt(session.quizId);

          return ListView(
            children: <Widget>[
              ArenaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        ArenaChip(label: session.category),
                        const SizedBox(width: 8),
                        const ArenaChip(label: 'CME'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(session.title, style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 16),
                    Text(session.topic, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 24),
                    ArenaCard(
                      color: const Color(0xFFF1F1F1),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: _Metric(icon: Icons.quiz_outlined, value: '${session.questionCount}', label: 'Questions')),
                          Expanded(child: _Metric(icon: Icons.timer_outlined, value: session.timeLimit, label: 'Time Limit')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ArenaCard(
                      color: const Color(0xFFF8F8F8),
                      child: Row(
                        children: <Widget>[
                          const CircleAvatar(child: Icon(Icons.person)),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('Hosted by', style: Theme.of(context).textTheme.labelMedium),
                              Text(session.host, style: Theme.of(context).textTheme.titleLarge),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ArenaButton(
                label: canStartRanked ? 'Ranked Mode' : 'Ranked Attempt Used',
                icon: Icons.emoji_events_outlined,
                onPressed: canStartRanked ? () => _startMode(session, QuizMode.ranked) : null,
              ),
              const SizedBox(height: 16),
              ArenaButton(
                label: 'Learning Mode',
                icon: Icons.school_outlined,
                backgroundColor: Colors.white,
                onPressed: () => _startMode(session, QuizMode.learning),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon),
        const SizedBox(height: 12),
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}