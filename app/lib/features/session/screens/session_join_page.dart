import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/monogram_avatar.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/repositories/profile_repository.dart';
import '../../quiz/repositories/quiz_repository.dart';
import '../events/last_session_recorded_event.dart';
import '../models/session_info.dart';
import '../repositories/session_repository.dart';
import '../storage/last_session_store.dart';

/// Session-join lobby (Slice 2c — Vibrant Pulse reskin). The host-declared
/// session `mode` already drives a single primary CTA (Gap 6); this rebuild
/// keeps every behaviour bit unchanged and reskins the surface:
///
/// * hero session card sits inside a soft purple→gold pulse glow with a
///   Poppins headline, ArenaChip metadata, KPI-style metric tiles, and a
///   MonogramAvatar host attribution row;
/// * primary CTA wrapped in `PressScale` + `Haptics.submit` so it shares the
///   home page's tap vocabulary;
/// * guest-nickname prompt switches to a `primarySoft` background with a
///   gold save CTA.
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
  late final ProfileRepository _profileRepository;
  Future<SessionInfo>? _futureSession;
  UserProfile? _profile;
  final GlobalKey _guestPromptKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _sessionRepository = getIt<SessionRepository>();
    _quizRepository = getIt<QuizRepository>();
    _lastSessionStore = getIt<LastSessionStore>();
    _eventBus = getIt<EventBus>();
    _profileRepository = getIt<ProfileRepository>();
    _futureSession = _loadSession();
    _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    final UserProfile? profile = await _profileRepository.getProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
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
    if (mode == QuizMode.ranked && _isGuestProfile) {
      _promptForNickname();
      return;
    }
    Haptics.submit();
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

  bool get _isGuestProfile {
    final UserProfile? profile = _profile;
    if (profile == null) return false;
    return ProfileRepository.isGuestNickname(profile.nickname);
  }

  void _promptForNickname() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pick a nickname to start ranked.')),
    );
    final BuildContext? promptContext = _guestPromptKey.currentContext;
    if (promptContext != null) {
      Scrollable.ensureVisible(
        promptContext,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
    }
  }

  Future<void> _saveNickname(String nickname) async {
    final UserProfile? existing = _profile;
    if (existing == null) return;
    final String trimmed = nickname.trim();
    if (trimmed.isEmpty || ProfileRepository.isGuestNickname(trimmed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a nickname other than the guest default.')),
      );
      return;
    }
    await _profileRepository.updateProfile(
      nickname: trimmed,
      facility: existing.facility,
      specialty: existing.specialty,
    );
    if (!mounted) return;
    await _refreshProfile();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Nickname set to @$trimmed.')),
    );
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
            return _ErrorState(
              error: snapshot.error,
              onRetry: () => setState(() => _futureSession = _loadSession()),
            );
          }
          if (!snapshot.hasData) {
            return _LoadingState(joinCode: widget.joinCode?.trim());
          }
          final SessionInfo session = snapshot.data!;
          final bool canStartRanked =
              _quizRepository.canStartRankedAttempt(session.quizId);

          return ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              if (_isGuestProfile)
                Padding(
                  padding: const EdgeInsets.only(bottom: MedRashSpace.lg),
                  child: _GuestNicknamePrompt(
                    key: _guestPromptKey,
                    currentNickname: _profile!.nickname,
                    onSave: _saveNickname,
                  ),
                ),
              _SessionHeroCard(session: session),
              const SizedBox(height: MedRashSpace.xl),
              // Host-declared mode (Gap 6) drives a single primary CTA. For
              // ranked sessions where the participant has already burned
              // their official attempt, surface a secondary "Switch to
              // Learning Mode" affordance so the lobby never dead-ends.
              if (session.mode == 'learning') ...<Widget>[
                _PrimarySessionCta(
                  label: 'Start Learning Mode',
                  icon: Icons.school_rounded,
                  onPressed: () => _startMode(session, QuizMode.learning),
                ),
              ] else ...<Widget>[
                _PrimarySessionCta(
                  label: canStartRanked
                      ? 'Start Ranked Mode'
                      : 'Ranked Attempt Used',
                  icon: Icons.emoji_events_rounded,
                  onPressed: canStartRanked
                      ? () => _startMode(session, QuizMode.ranked)
                      : null,
                ),
                if (!canStartRanked) ...<Widget>[
                  const SizedBox(height: MedRashSpace.md),
                  ArenaButton(
                    label: 'Switch to Learning Mode',
                    icon: Icons.school_rounded,
                    backgroundColor: Colors.white,
                    onPressed: () => _startMode(session, QuizMode.learning),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SessionHeroCard extends StatelessWidget {
  const _SessionHeroCard({required this.session});

  final SessionInfo session;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Stack(
      children: <Widget>[
        // Soft purple→gold pulse glow behind the card. Static (not animated)
        // so the motion budget stays reserved for the primary CTA and any
        // future quiz-start transition.
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusLarge + 4),
              gradient: LinearGradient(
                colors: <Color>[
                  tokens.primary.withValues(alpha: 0.22),
                  tokens.secondary.withValues(alpha: 0.22),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.primary.withValues(alpha: 0.18),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ),
        ArenaCard(
          padding: const EdgeInsets.all(MedRashSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  ArenaChip(label: session.category),
                  const SizedBox(width: MedRashSpace.sm),
                  const ArenaChip(label: 'CME'),
                ],
              ),
              const SizedBox(height: MedRashSpace.lg),
              Text(
                session.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
              ),
              const SizedBox(height: MedRashSpace.sm),
              Text(
                session.topic,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
              ),
              const SizedBox(height: MedRashSpace.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.quiz_rounded,
                      value: '${session.questionCount}',
                      label: 'Questions',
                      tint: tokens.primary,
                      tintBackground: tokens.primarySoft,
                    ),
                  ),
                  const SizedBox(width: MedRashSpace.md),
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.timer_rounded,
                      value: session.timeLimit,
                      label: 'Time Limit',
                      tint: tokens.onSecondary,
                      tintBackground: tokens.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MedRashSpace.md),
              _HostRow(host: session.host),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
    required this.tintBackground,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color tint;
  final Color tintBackground;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tintBackground,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: tint, size: MedRashIconSize.lg),
          ),
          const SizedBox(height: MedRashSpace.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                  height: 1,
                ),
          ),
          const SizedBox(height: MedRashSpace.xs),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Container(
      padding: const EdgeInsets.all(MedRashSpace.md),
      decoration: BoxDecoration(
        color: tokens.primarySoft,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Row(
        children: <Widget>[
          MonogramAvatar(
            source: host,
            diameter: 40,
            backgroundColor: tokens.secondary,
            foregroundColor: tokens.onSecondary,
          ),
          const SizedBox(width: MedRashSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'HOSTED BY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.primaryStrong,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  host,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimarySessionCta extends StatelessWidget {
  const _PrimarySessionCta({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool enabled = onPressed != null;
    return PressScale(
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: ArenaButton(
          label: label,
          icon: icon,
          backgroundColor: tokens.secondary,
          foregroundColor: tokens.onSecondary,
          onPressed: enabled ? onPressed : null,
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.joinCode});

  final String? joinCode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircularProgressIndicator(color: tokens.primary),
          const SizedBox(height: MedRashSpace.md),
          Text(
            joinCode != null && joinCode!.isNotEmpty
                ? 'Joining session $joinCode\u2026'
                : 'Loading session\u2026',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String message = error is StateError
        ? (error as StateError).message.toString()
        : 'Unable to load session right now.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            color: tokens.primary,
            size: MedRashIconSize.xl,
          ),
          const SizedBox(height: MedRashSpace.md),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MedRashSpace.md),
          PressScale(
            onTap: onRetry,
            child: ArenaButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              backgroundColor: tokens.secondary,
              foregroundColor: tokens.onSecondary,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestNicknamePrompt extends StatefulWidget {
  const _GuestNicknamePrompt({
    super.key,
    required this.currentNickname,
    required this.onSave,
  });

  final String currentNickname;
  final Future<void> Function(String nickname) onSave;

  @override
  State<_GuestNicknamePrompt> createState() => _GuestNicknamePromptState();
}

class _GuestNicknamePromptState extends State<_GuestNicknamePrompt> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.primarySoft,
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Pick a nickname for the leaderboard',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: tokens.primaryStrong,
                ),
          ),
          const SizedBox(height: MedRashSpace.xs),
          Text(
            'Optional for Learning. Required before Ranked. Joined as @${widget.currentNickname}.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
          const SizedBox(height: MedRashSpace.md),
          TextField(
            controller: _controller,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(32),
            ],
            decoration: InputDecoration(
              labelText: 'Nickname',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                borderSide:
                    BorderSide(color: tokens.outline, width: tokens.borderWidth),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                borderSide:
                    BorderSide(color: tokens.outline, width: tokens.borderWidth),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                borderSide: BorderSide(color: tokens.primary, width: 2),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: MedRashSpace.md),
          PressScale(
            enabled: !_saving,
            onTap: _saving
                ? null
                : () {
                    Haptics.submit();
                    _submit();
                  },
            child: ArenaButton(
              label: _saving ? 'Saving\u2026' : 'Save nickname',
              icon: Icons.check_rounded,
              backgroundColor: tokens.secondary,
              foregroundColor: tokens.onSecondary,
              onPressed: _saving ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }
}
