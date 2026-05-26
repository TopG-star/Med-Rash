import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/identity_snapshot.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/operation_runner_state.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/monogram_avatar.dart';
import '../repositories/profile_repository.dart';

class QuickJoinPage extends StatefulWidget {
  const QuickJoinPage({super.key, this.nextPath});

  /// Optional post-onboarding destination (e.g. `/session/ABCD`). Honored only
  /// when it is a safe in-app path; falls back to `/home` otherwise.
  final String? nextPath;

  @override
  State<QuickJoinPage> createState() => _QuickJoinPageState();
}

class _QuickJoinPageState extends State<QuickJoinPage>
    with OperationRunnerState<QuickJoinPage> {
  static const List<String> _specialties = <String>[
    'Doctor',
    'Pharmacist',
    'Nurse',
    'Medical Rep',
  ];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _facilityController = TextEditingController();
  late final ProfileRepository _profileRepository;
  late final AuthStateManager _authStateManager;
  String _specialty = 'Doctor';
  String _nickname = '';

  @override
  void initState() {
    super.initState();
    _profileRepository = getIt<ProfileRepository>();
    _authStateManager = getIt<AuthStateManager>();
    _nickname = _profileRepository.generateNickname();
    _authStateManager.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authStateManager.removeListener(_onAuthChanged);
    _nameController.dispose();
    _facilityController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _regenerateNickname() {
    Haptics.selection();
    setState(() {
      _nickname = _profileRepository.generateNickname(
        fullName: _nameController.text,
      );
    });
  }

  Future<void> _resumeSnapshot(IdentitySnapshot snapshot) async {
    Haptics.submit();
    await runOperation(() async {
      await _profileRepository.restoreFromSnapshot(snapshot);
      await _authStateManager.restoreFromSnapshot(snapshot);
    });
    if (mounted) {
      context.go(widget.nextPath ?? '/home');
    }
  }

  Future<void> _startFresh() async {
    await _authStateManager.dismissLastSnapshot();
  }

  Future<void> _submit() async {
    Haptics.submit();
    await runOperation(() async {
      await _profileRepository.quickJoin(
        fullName: _nameController.text,
        facility: _facilityController.text,
        specialty: _specialty,
        nickname: _nickname,
      );
      await getIt<AuthStateManager>().markJoined();
    });
    if (mounted) {
      context.go(widget.nextPath ?? '/home');
    }
  }

  bool get _canStart {
    return _nameController.text.trim().isNotEmpty &&
        _facilityController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final IdentitySnapshot? snapshot = _authStateManager.lastSignedOutSnapshot;
    final String? joiningCode = joinCodeFromNextPath(widget.nextPath);
    final bool showHero = snapshot == null && joiningCode == null;
    final String ctaLabel = joiningCode != null
        ? 'Continue to session $joiningCode'
        : 'Start Playing';

    return ArenaScaffold(
      title: 'Join The Academy',
      showBack: false,
      child: MedRashConstrainedBody(
        child: ListView(
          children: <Widget>[
            if (joiningCode != null) ...<Widget>[
              _SessionContextCard(joinCode: joiningCode),
              const SizedBox(height: MedRashSpace.lg),
            ],
            if (snapshot != null) ...<Widget>[
              _ResumeCard(
                snapshot: snapshot,
                joiningCode: joiningCode,
                onResume: () => _resumeSnapshot(snapshot),
                onStartFresh: _startFresh,
              ),
              const SizedBox(height: MedRashSpace.xl),
            ],
            if (showHero) ...<Widget>[
              const _HeroIntro(),
              const SizedBox(height: MedRashSpace.lg),
            ],
            _OnboardingCard(
              nameController: _nameController,
              facilityController: _facilityController,
              specialty: _specialty,
              specialties: _specialties,
              nickname: _nickname,
              onNameChanged: (String value) {
                setState(() {
                  if (value.trim().isNotEmpty) {
                    _nickname =
                        _profileRepository.generateNickname(fullName: value);
                  }
                });
              },
              onFacilityChanged: (_) => setState(() {}),
              onSpecialtyChanged: (String value) {
                Haptics.selection();
                setState(() => _specialty = value);
              },
              onRegenerateNickname: _regenerateNickname,
            ),
            const SizedBox(height: MedRashSpace.xl),
            PressScale(
              onTap: _canStart ? _submit : null,
              child: ArenaButton(
                label: ctaLabel,
                onPressed: _canStart ? _submit : null,
                backgroundColor: context.arenaTokens.secondary,
                foregroundColor: context.arenaTokens.onSecondary,
                icon: Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(height: MedRashSpace.lg),
          ],
        ),
      ),
    );
  }
}

class _HeroIntro extends StatelessWidget {
  const _HeroIntro();

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Welcome to MedRash.',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
        ),
        const SizedBox(height: MedRashSpace.xs),
        Text(
          'Tell us who you are. We will hand you a leaderboard handle and you '
          'jump straight into the arena.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.nameController,
    required this.facilityController,
    required this.specialty,
    required this.specialties,
    required this.nickname,
    required this.onNameChanged,
    required this.onFacilityChanged,
    required this.onSpecialtyChanged,
    required this.onRegenerateNickname,
  });

  final TextEditingController nameController;
  final TextEditingController facilityController;
  final String specialty;
  final List<String> specialties;
  final String nickname;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onFacilityChanged;
  final ValueChanged<String> onSpecialtyChanged;
  final VoidCallback onRegenerateNickname;

  @override
  Widget build(BuildContext context) {
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FocusInput(
            label: 'Full name',
            controller: nameController,
            hintText: 'Enter your full name',
            textCapitalization: TextCapitalization.words,
            keyboardType: TextInputType.name,
            autofillHints: const <String>[AutofillHints.name],
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(64),
            ],
            onChanged: onNameChanged,
          ),
          const SizedBox(height: MedRashSpace.lg),
          _FocusInput(
            label: 'Facility',
            controller: facilityController,
            hintText: 'e.g. Korle-Bu Teaching Hospital',
            textCapitalization: TextCapitalization.words,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(80),
            ],
            onChanged: onFacilityChanged,
          ),
          const SizedBox(height: MedRashSpace.lg),
          _FocusDropdown(
            label: 'Specialty',
            value: specialty,
            options: specialties,
            onChanged: onSpecialtyChanged,
          ),
          const SizedBox(height: MedRashSpace.xl),
          _NicknameChip(
            nickname: nickname,
            onRegenerate: onRegenerateNickname,
          ),
        ],
      ),
    );
  }
}

class _FocusInput extends StatefulWidget {
  const _FocusInput({
    required this.label,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
    this.autofillHints,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_FocusInput> createState() => _FocusInputState();
}

class _FocusInputState extends State<_FocusInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool focused = _focusNode.hasFocus;
    final Color borderColor = focused ? tokens.primary : tokens.outline;
    final double borderWidth = focused ? 2.0 : tokens.borderWidth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: focused ? tokens.primary : tokens.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
        ),
        const SizedBox(height: MedRashSpace.sm),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: focused ? tokens.primarySoft : tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            textCapitalization: widget.textCapitalization,
            keyboardType: widget.keyboardType,
            autofillHints: widget.autofillHints,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            cursorColor: tokens.primary,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: widget.hintText,
              border: InputBorder.none,
              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FocusDropdown extends StatelessWidget {
  const _FocusDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
        ),
        const SizedBox(height: MedRashSpace.sm),
        Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border:
                Border.all(color: tokens.outline, width: tokens.borderWidth),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              // Netlify build pins Flutter 3.27.4 where `initialValue` doesn't exist yet.
              // ignore: deprecated_member_use
              value: value,
              isExpanded: true,
              icon: Icon(
                Icons.expand_more_rounded,
                color: tokens.textPrimary,
                size: MedRashIconSize.md,
              ),
              style: Theme.of(context).textTheme.bodyLarge,
              dropdownColor: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
              items: options
                  .map((String v) => DropdownMenuItem<String>(
                        value: v,
                        child: Text(v),
                      ))
                  .toList(),
              onChanged: (String? v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NicknameChip extends StatelessWidget {
  const _NicknameChip({
    required this.nickname,
    required this.onRegenerate,
  });

  final String nickname;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'YOUR ARENA HANDLE',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
        ),
        const SizedBox(height: MedRashSpace.sm),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: tokens.primarySoft,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(
              color: tokens.primary.withValues(alpha: 0.25),
              width: tokens.borderWidth,
            ),
          ),
          child: Row(
            children: <Widget>[
              MonogramAvatar(
                source: nickname,
                diameter: 44,
                backgroundColor: tokens.secondary,
                foregroundColor: tokens.onSecondary,
              ),
              const SizedBox(width: MedRashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder:
                          (Widget child, Animation<double> anim) =>
                              FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        nickname,
                        key: ValueKey<String>(nickname),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              color: tokens.primaryStrong,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'Ready for the leaderboard',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              PressScale(
                onTap: onRegenerate,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tokens.primary.withValues(alpha: 0.3),
                      width: tokens.borderWidth,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: MedRashIconSize.md,
                    color: tokens.primary,
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

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.snapshot,
    required this.onResume,
    required this.onStartFresh,
    this.joiningCode,
  });

  final IdentitySnapshot snapshot;
  final VoidCallback onResume;
  final VoidCallback onStartFresh;
  final String? joiningCode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.primarySoft,
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              MonogramAvatar(
                source: snapshot.nickname.isNotEmpty
                    ? snapshot.nickname
                    : 'Returning Player',
                diameter: 48,
                backgroundColor: tokens.secondary,
                foregroundColor: tokens.onSecondary,
              ),
              const SizedBox(width: MedRashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'WELCOME BACK',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: tokens.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snapshot.nickname.isNotEmpty
                          ? snapshot.nickname
                          : 'Returning player',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            color: tokens.primaryStrong,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (snapshot.facility.isNotEmpty)
                      Text(
                        snapshot.facility,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.lg),
          PressScale(
            onTap: onResume,
            child: ArenaButton(
              label: _resumeLabel(),
              onPressed: onResume,
              backgroundColor: tokens.secondary,
              foregroundColor: tokens.onSecondary,
            ),
          ),
          const SizedBox(height: MedRashSpace.xs),
          TextButton(
            onPressed: onStartFresh,
            child: Text(
              'Not you? Start fresh',
              style: TextStyle(color: tokens.primary),
            ),
          ),
        ],
      ),
    );
  }

  String _resumeLabel() {
    final String who = snapshot.nickname.isNotEmpty
        ? snapshot.nickname
        : 'previous player';
    if (joiningCode != null) {
      return 'Continue as $who → session $joiningCode';
    }
    return 'Continue as $who';
  }
}

class _SessionContextCard extends StatelessWidget {
  const _SessionContextCard({required this.joinCode});

  final String joinCode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.secondary,
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.qr_code_2_rounded,
                color: tokens.onSecondary,
                size: MedRashIconSize.lg,
              ),
              const SizedBox(width: MedRashSpace.sm),
              Expanded(
                child: Text(
                  "You're joining session $joinCode",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.onSecondary,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.xs),
          Text(
            "Choose a nickname and you'll join the session right after.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.onSecondary.withValues(alpha: 0.85),
                ),
          ),
        ],
      ),
    );
  }
}