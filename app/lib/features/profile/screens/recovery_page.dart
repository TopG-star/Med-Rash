import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/operation_runner_state.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../quiz/storage/ranked_best_score_store.dart';
import '../../session/storage/last_session_store.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../repositories/recovery_repository.dart';

enum _RecoveryStep { requestEmail, verifyCode }

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage>
    with OperationRunnerState<RecoveryPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  late final RecoveryRepository _recoveryRepository;
  late final AuthStateManager _authStateManager;
  late final ProfileRepository _profileRepository;
  late final EventBus _eventBus;
  late final LastSessionStore _lastSessionStore;
  late final RankedBestScoreStore _rankedBestScoreStore;

  // Conservative shape check, mirrors quick_join_page._emailFormat and the
  // server-side EMAIL_REGEX so the verdict is identical on every surface.
  static final RegExp _emailFormat = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  _RecoveryStep _step = _RecoveryStep.requestEmail;
  String? _emailError;
  String? _codeError;
  String? _banner;
  String? _bannerKind; // 'error' | 'success' | 'info'
  String _normalizedEmail = '';
  int _resendCooldownSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _recoveryRepository = getIt<RecoveryRepository>();
    _authStateManager = getIt<AuthStateManager>();
    _profileRepository = getIt<ProfileRepository>();
    _eventBus = getIt<EventBus>();
    _lastSessionStore = getIt<LastSessionStore>();
    _rankedBestScoreStore = getIt<RankedBestScoreStore>();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sessionInProgress = _lastSessionStore.read() != null;

    return ArenaScaffold(
      title: 'Recover Profile',
      showBack: true,
      child: MedRashConstrainedBody(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            if (sessionInProgress)
              _buildSessionBlocker(context)
            else if (_step == _RecoveryStep.requestEmail)
              _buildRequestStep(context)
            else
              _buildVerifyStep(context),
          ],
        ),
      ),
    );
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_authStateManager.hasProfile ? '/home' : '/join');
    }
  }

  Widget _buildSessionBlocker(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Finish your current session first',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recovery rebinds this device to another profile and will replace your current participant id. Leave or finish your in-progress session before continuing.',
              style: TextStyle(color: tokens.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            ArenaButton(
              label: 'Back',
              onPressed: _handleBack,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestStep(BuildContext context) {
    final tokens = context.arenaTokens;
    final Map<String, int> bestScores = _rankedBestScoreStore.snapshot();
    final int localAttemptCount = bestScores.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Enter the email tied to your original profile. We\u2019ll send a 6-digit code to confirm it\u2019s really you.',
          style: TextStyle(color: tokens.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),
        if (localAttemptCount > 0)
          _MergeWarningCard(localAttemptCount: localAttemptCount),
        if (localAttemptCount > 0) const SizedBox(height: 20),
        if (_banner != null) ...<Widget>[
          _Banner(message: _banner!, kind: _bannerKind ?? 'error'),
          const SizedBox(height: 16),
        ],
        Text('RECOVERY EMAIL', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        _PlainArenaTextField(
          controller: _emailController,
          hintText: 'you@hospital.org',
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) {
            if (_emailError != null) {
              setState(() => _emailError = null);
            }
          },
        ),
        if (_emailError != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(_emailError!, style: TextStyle(color: tokens.error, fontSize: 13)),
        ],
        const SizedBox(height: 28),
        ArenaButton(
          label: 'Send recovery code',
          onPressed: _submitEmail,
        ),
      ],
    );
  }

  Widget _buildVerifyStep(BuildContext context) {
    final tokens = context.arenaTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'We sent a 6-digit code to:',
          style: TextStyle(color: tokens.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 4),
        Text(
          _normalizedEmail,
          style: TextStyle(color: tokens.textPrimary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        if (_banner != null) ...<Widget>[
          _Banner(message: _banner!, kind: _bannerKind ?? 'error'),
          const SizedBox(height: 16),
        ],
        Text('6-DIGIT CODE', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        _PlainArenaTextField(
          controller: _codeController,
          hintText: '123456',
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) {
            if (_codeError != null) {
              setState(() => _codeError = null);
            }
          },
        ),
        if (_codeError != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(_codeError!, style: TextStyle(color: tokens.error, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        ArenaButton(
          label: 'Verify and recover',
          onPressed: _submitCode,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _resendCooldownSeconds > 0 ? null : _resendCode,
            child: Text(
              _resendCooldownSeconds > 0
                  ? 'Resend code in ${_resendCooldownSeconds}s'
                  : 'Resend code',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
                  _step = _RecoveryStep.requestEmail;
                  _codeController.clear();
                  _codeError = null;
                  _banner = null;
                  _bannerKind = null;
                }),
            child: const Text('Use a different email'),
          ),
        ),
      ],
    );
  }

  Future<void> _submitEmail() async {
    final String raw = _emailController.text.trim().toLowerCase();
    if (raw.isEmpty || raw.length > 254 || !_emailFormat.hasMatch(raw)) {
      setState(() => _emailError = 'Enter a valid email.');
      return;
    }
    setState(() {
      _emailError = null;
      _banner = null;
      _bannerKind = null;
    });

    await runOperation(() async {
      try {
        await _recoveryRepository.requestOtp(email: raw);
        if (!mounted) return;
        setState(() {
          _step = _RecoveryStep.verifyCode;
          _normalizedEmail = raw;
          _banner = 'We just sent a 6-digit code to $raw. It expires in a few minutes.';
          _bannerKind = 'success';
        });
        _startResendCooldown();
      } on RecoveryException catch (error) {
        if (!mounted) return;
        setState(() {
          _banner = _humanReadable(error);
          _bannerKind = 'error';
        });
      }
    });
  }

  Future<void> _submitCode() async {
    final String code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _codeError = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _codeError = null;
      _banner = null;
      _bannerKind = null;
    });

    await runOperation(() async {
      try {
        final RecoveredIdentity recovered = await _recoveryRepository.verifyOtp(
          email: _normalizedEmail,
          otp: code,
        );
        await _authStateManager.adoptRecoveredIdentity(
          participantId: recovered.participantId,
          deviceInstallId: recovered.deviceInstallId,
        );
        final UserProfile persisted =
            await _profileRepository.persistRecoveredProfile(recovered.profile);
        // Tell every identity-keyed cache (ranked best scores, leaderboard
        // snapshot, persisted attempts) that the participant id rotated.
        // keptDeviceId=true mirrors the server: install id stayed, only the
        // user_id swapped via merge.
        _eventBus.emit(const IdentityResetEvent(keptDeviceId: true));

        if (!mounted) return;
        _showRecoveredSnack(persisted);
        context.go('/home');
      } on RecoveryException catch (error) {
        if (!mounted) return;
        setState(() {
          _banner = _humanReadable(error);
          _bannerKind = 'error';
          if (error is OtpInvalidException) {
            _codeError = 'The code didn\u2019t match. Check your email and try again.';
          }
        });
      }
    });
  }

  Future<void> _resendCode() async {
    if (_normalizedEmail.isEmpty) return;
    await runOperation(() async {
      try {
        await _recoveryRepository.requestOtp(email: _normalizedEmail);
        if (!mounted) return;
        setState(() {
          _banner = 'We sent a fresh code to $_normalizedEmail.';
          _bannerKind = 'success';
        });
        _startResendCooldown();
      } on RecoveryException catch (error) {
        if (!mounted) return;
        setState(() {
          _banner = _humanReadable(error);
          _bannerKind = 'error';
        });
      }
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldownSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldownSeconds -= 1;
        if (_resendCooldownSeconds <= 0) {
          t.cancel();
          _resendCooldownSeconds = 0;
        }
      });
    });
  }

  void _showRecoveredSnack(UserProfile profile) {
    final String name =
        profile.nickname.isNotEmpty ? profile.nickname : profile.fullName;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Welcome back, $name.')),
    );
  }

  String _humanReadable(RecoveryException error) {
    if (error is ProfileNotFoundException) {
      return 'No profile found for that email. Double-check the address or start fresh from Join.';
    }
    if (error is OtpInvalidException) {
      return 'That code is wrong or expired. Request a new one and try again.';
    }
    if (error is RecoveryRateLimitedException) {
      return 'Too many recovery attempts. Wait a minute and try again.';
    }
    if (error is OtpDeliveryFailedException) {
      return 'We couldn\u2019t send the code right now. Try again in a moment.';
    }
    if (error is RecoveryConflictException) {
      return 'That email is locked to a different sign-in. Contact support.';
    }
    return error.message;
  }
}

class _MergeWarningCard extends StatelessWidget {
  const _MergeWarningCard({required this.localAttemptCount});

  final int localAttemptCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String quizWord = localAttemptCount == 1 ? 'quiz' : 'quizzes';
    return ArenaCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.merge_type_rounded, color: tokens.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You\u2019ve already played $localAttemptCount $quizWord on this device. Those attempts will be merged into your recovered profile.',
                style: TextStyle(color: tokens.textSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.kind});

  final String message;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color color = switch (kind) {
      'success' => tokens.success,
      'info' => tokens.primary,
      _ => tokens.error,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: tokens.textPrimary, height: 1.4)),
    );
  }
}

class _PlainArenaTextField extends StatelessWidget {
  const _PlainArenaTextField({
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          hintStyle: TextStyle(color: tokens.textSecondary),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
