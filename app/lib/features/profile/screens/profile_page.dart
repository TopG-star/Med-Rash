import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/motion/count_up_number.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/ui/widgets/empty_state.dart';
import '../../../core/ui/widgets/monogram_avatar.dart';
import '../../quiz/storage/quiz_attempt_store.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileRepository _profileRepository;
  UserProfile? _profile;
  late final TextEditingController _nicknameController = TextEditingController();
  late final TextEditingController _facilityController = TextEditingController();
  String _specialty = 'Emergency Medicine';
  bool _saving = false;
  StreamSubscription<ProfilePointsUpdatedEvent>? _pointsSubscription;

  @override
  void initState() {
    super.initState();
    _profileRepository = getIt<ProfileRepository>();
    _loadProfile();
    _pointsSubscription = getIt<EventBus>()
        .on<ProfilePointsUpdatedEvent>()
        .listen((_) => _loadProfile());
  }

  @override
  void dispose() {
    _pointsSubscription?.cancel();
    _nicknameController.dispose();
    _facilityController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final UserProfile? profile = await _profileRepository.getProfile();
    if (!mounted || profile == null) {
      return;
    }

    setState(() {
      _profile = profile;
      _nicknameController.text = profile.nickname;
      _facilityController.text = profile.facility;
      _specialty = profile.specialty;
    });
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      Haptics.submit();
      final UserProfile updated = await _profileRepository.updateProfile(
        nickname: _nicknameController.text,
        facility: _facilityController.text,
        specialty: _specialty,
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile saved.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      return const ArenaScaffold(
        title: 'Profile',
        showBack: true,
        bottomNav: true,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: MedRashSkeletonCard(),
        ),
      );
    }

    final UserProfile profile = _profile!;

    return ArenaScaffold(
      title: 'Profile',
      showBack: true,
      bottomNav: true,
      child: MedRashConstrainedBody(
        child: ListView(
          children: <Widget>[
            _ProfileHero(profile: profile),
            const SizedBox(height: MedRashSpace.lg),
            _StatsRow(profile: profile),
            if (profile.totalPoints <= 0 && profile.rank <= 0) ...<Widget>[
              const SizedBox(height: MedRashSpace.lg),
              MedRashEmptyState(
                icon: Icons.history_edu_rounded,
                title: 'No ranked attempts yet',
                body:
                    'Your ranked history lights up here once you finish your first ranked quiz. Tap below to start logging clinical reps.',
                ctaLabel: 'Browse ranked quizzes',
                onCta: () => context.go('/ranked'),
              ),
            ],
            const SizedBox(height: MedRashSpace.xl),
            const _SectionLabel(label: 'IDENTITY'),
            const SizedBox(height: MedRashSpace.sm),
            _ProfileField(
              label: 'Nickname',
              icon: Icons.alternate_email_rounded,
              controller: _nicknameController,
              hintText: '@yourname',
              maxLength: 32,
            ),
            const SizedBox(height: MedRashSpace.md),
            _ProfileField(
              label: 'Facility',
              icon: Icons.local_hospital_rounded,
              controller: _facilityController,
              hintText: 'Where you train or practice',
            ),
            const SizedBox(height: MedRashSpace.md),
            _SpecialtyField(
              value: _specialty,
              onChanged: (String value) => setState(() => _specialty = value),
            ),
            const SizedBox(height: MedRashSpace.xl),
            PressScale(
              enabled: !_saving,
              onTap: _saving ? null : _saveProfile,
              child: ArenaButton(
                label: _saving ? 'Saving\u2026' : 'Save Profile',
                icon: Icons.check_circle_rounded,
                backgroundColor: context.arenaTokens.secondary,
                foregroundColor: context.arenaTokens.onSecondary,
                onPressed: _saving ? null : _saveProfile,
              ),
            ),
            const SizedBox(height: MedRashSpace.xl),
            const _ClaimAccountCard(),
            const SizedBox(height: MedRashSpace.lg),
            _SignOutCard(onSignOut: _showSignOutSheet),
          ],
        ),
      ),
    );
  }

  Future<void> _showSignOutSheet() async {
    final _SignOutChoice? choice = await showModalBottomSheet<_SignOutChoice>(
      context: context,
      backgroundColor: context.arenaTokens.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext sheetContext) => _SignOutSheet(),
    );

    if (choice == null || !mounted) {
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);
    final ProfileRepository profileRepo = _profileRepository;
    final QuizAttemptStore attemptStore = getIt<QuizAttemptStore>();
    final AuthStateManager auth = getIt<AuthStateManager>();
    final EventBus eventBus = getIt<EventBus>();

    final bool keepDeviceId = choice == _SignOutChoice.keepDevice;

    // Capture profile BEFORE clearAll so the soft-sign-out branch can write
    // a resume snapshot. The hard-sign-out branch ignores it.
    final UserProfile? snapshotProfile =
        keepDeviceId ? await profileRepo.getProfile() : null;

    await profileRepo.clearAll();
    await attemptStore.clearActive();
    await attemptStore.clearCompleted();
    await auth.signOut(
      keepDeviceId: keepDeviceId,
      profile: snapshotProfile == null
          ? null
          : ProfileSnapshotInput(
              fullName: snapshotProfile.fullName,
              nickname: snapshotProfile.nickname,
              facility: snapshotProfile.facility,
              specialty: snapshotProfile.specialty,
              totalPoints: snapshotProfile.totalPoints,
              rank: snapshotProfile.rank,
            ),
    );
    eventBus.emit(IdentityResetEvent(keptDeviceId: keepDeviceId));

    if (!mounted) {
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Signed out.')));
    router.go('/join');
  }
}

enum _SignOutChoice { keepDevice, rotateDevice }

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String displayName =
        profile.fullName.trim().isEmpty ? profile.nickname : profile.fullName;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusLarge + 4),
              gradient: LinearGradient(
                colors: <Color>[
                  tokens.primary.withValues(alpha: 0.28),
                  tokens.secondary.withValues(alpha: 0.28),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.primary.withValues(alpha: 0.22),
                  blurRadius: 26,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
        ),
        ArenaCard(
          padding: const EdgeInsets.all(MedRashSpace.xl),
          child: Column(
            children: <Widget>[
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.primarySoft,
                  border: Border.all(color: tokens.secondary, width: 3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: tokens.secondary.withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: MonogramAvatar(
                  source: profile.nickname.isEmpty
                      ? profile.fullName
                      : profile.nickname,
                  diameter: 100,
                  backgroundColor: tokens.primary,
                  foregroundColor: Colors.white,
                  textStyle: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: MedRashSpace.md),
              Text(
                displayName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
              ),
              const SizedBox(height: MedRashSpace.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MedRashSpace.md,
                  vertical: MedRashSpace.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: tokens.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: tokens.outline,
                    width: tokens.borderWidth,
                  ),
                ),
                child: Text(
                  '@${profile.nickname}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.primaryStrong,
                      ),
                ),
              ),
              if (profile.specialty.isNotEmpty ||
                  profile.facility.isNotEmpty) ...<Widget>[
                const SizedBox(height: MedRashSpace.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: MedRashSpace.sm,
                  runSpacing: MedRashSpace.xs,
                  children: <Widget>[
                    if (profile.specialty.isNotEmpty)
                      _MetaChip(
                        icon: Icons.medical_services_rounded,
                        label: profile.specialty,
                      ),
                    if (profile.facility.isNotEmpty)
                      _MetaChip(
                        icon: Icons.location_city_rounded,
                        label: profile.facility,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.sm + 2,
        vertical: MedRashSpace.xs + 1,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: tokens.textSecondary, size: MedRashIconSize.sm),
          const SizedBox(width: MedRashSpace.xs + 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatTile(
            label: 'TOTAL POINTS',
            value: profile.totalPoints,
            icon: Icons.military_tech_rounded,
            iconColor: tokens.primary,
            iconSurface: tokens.primarySoft,
          ),
        ),
        const SizedBox(width: MedRashSpace.md),
        Expanded(
          child: _StatTile(
            label: 'WORLD RANK',
            value: profile.rank,
            icon: Icons.emoji_events_rounded,
            iconColor: tokens.onSecondary,
            iconSurface: tokens.secondary,
            formatter: (int v) => v <= 0 ? '\u2014' : '#$v',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconSurface,
    this.formatter,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color iconColor;
  final Color iconSurface;
  final String Function(int v)? formatter;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      padding: const EdgeInsets.all(MedRashSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconSurface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: MedRashIconSize.md),
          ),
          const SizedBox(height: MedRashSpace.sm),
          CountUpNumber(
            value: value,
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            formatter: formatter,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                  height: 1,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Padding(
      padding: const EdgeInsets.only(left: MedRashSpace.xs),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              color: tokens.textSecondary,
              letterSpacing: 1.0,
            ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.icon,
    required this.controller,
    this.hintText,
    this.maxLength,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String? hintText;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      padding: const EdgeInsets.fromLTRB(
        MedRashSpace.md,
        MedRashSpace.md,
        MedRashSpace.md,
        MedRashSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: tokens.primary, size: MedRashIconSize.md),
              const SizedBox(width: MedRashSpace.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary,
                      letterSpacing: 0.6,
                    ),
              ),
            ],
          ),
          TextField(
            controller: controller,
            maxLength: maxLength,
            inputFormatters: maxLength != null
                ? <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(maxLength),
                  ]
                : null,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
            decoration: InputDecoration(
              border: InputBorder.none,
              counterText: '',
              hintText: hintText,
              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary.withValues(alpha: 0.7),
                  ),
              isDense: true,
              contentPadding: const EdgeInsets.only(top: MedRashSpace.sm),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialtyField extends StatelessWidget {
  const _SpecialtyField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      padding: const EdgeInsets.fromLTRB(
        MedRashSpace.md,
        MedRashSpace.md,
        MedRashSpace.md,
        MedRashSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.medical_services_rounded,
                color: tokens.primary,
                size: MedRashIconSize.md,
              ),
              const SizedBox(width: MedRashSpace.sm),
              Text(
                'Specialty',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary,
                      letterSpacing: 0.6,
                    ),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            // Netlify build pins Flutter 3.27.4 where `initialValue` doesn't exist yet.
            // ignore: deprecated_member_use
            value: value,
            isExpanded: true,
            icon: Icon(
              Icons.expand_more_rounded,
              color: tokens.primary,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.only(top: MedRashSpace.sm),
            ),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
            items: const <String>[
              'Emergency Medicine',
              'Pharmacy',
              'General Practice',
            ]
                .map(
                  (String v) => DropdownMenuItem<String>(
                    value: v,
                    child: Text(v),
                  ),
                )
                .toList(),
            onChanged: (String? v) {
              if (v != null) {
                Haptics.selection();
                onChanged(v);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ClaimAccountCard extends StatelessWidget {
  const _ClaimAccountCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.primarySoft,
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: MedRashIconSize.md,
                ),
              ),
              const SizedBox(width: MedRashSpace.md),
              Expanded(
                child: Text(
                  'Secure Your Progress',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        color: tokens.primaryStrong,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MedRashSpace.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: tokens.secondary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'SOON',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        color: tokens.onSecondary,
                        letterSpacing: 0.8,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.md),
          Text(
            'Add an email or phone number to claim this account and save your rank across devices.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.primaryStrong,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: MedRashSpace.lg),
          Opacity(
            opacity: 0.55,
            child: ArenaButton(
              label: 'Claim Account',
              icon: Icons.shield_rounded,
              backgroundColor: Colors.white,
              foregroundColor: tokens.primaryStrong,
              onPressed: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutCard extends StatelessWidget {
  const _SignOutCard({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.dangerSurface,
      padding: const EdgeInsets.all(MedRashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.error,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: MedRashIconSize.md,
                ),
              ),
              const SizedBox(width: MedRashSpace.md),
              Expanded(
                child: Text(
                  'Sign Out',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        color: tokens.error,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MedRashSpace.md),
          Text(
            'Clear your profile from this device. Your leaderboard rank stays attached to whatever identity you sign in as next.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: MedRashSpace.lg),
          PressScale(
            onTap: onSignOut,
            child: ArenaButton(
              label: 'Sign Out',
              icon: Icons.logout_rounded,
              backgroundColor: tokens.error,
              foregroundColor: Colors.white,
              onPressed: onSignOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MedRashSpace.lg,
          MedRashSpace.sm,
          MedRashSpace.lg,
          MedRashSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Sign out of MedRash?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
            ),
            const SizedBox(height: MedRashSpace.md),
            _SignOutOptionCard(
              icon: Icons.phone_iphone_rounded,
              iconColor: tokens.primary,
              iconSurface: tokens.primarySoft,
              title: 'Just sign me out on this device',
              body:
                  'You stay anonymous; signing back in with the same name puts you on the same leaderboard row.',
              onTap: () => Navigator.of(context).pop(_SignOutChoice.keepDevice),
            ),
            const SizedBox(height: MedRashSpace.md),
            _SignOutOptionCard(
              icon: Icons.group_rounded,
              iconColor: tokens.onSecondary,
              iconSurface: tokens.secondary,
              title: 'Hand to someone else',
              body:
                  'Treats this device as new. The next person joins as a separate leaderboard row.',
              onTap: () =>
                  Navigator.of(context).pop(_SignOutChoice.rotateDevice),
            ),
            const SizedBox(height: MedRashSpace.md),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignOutOptionCard extends StatelessWidget {
  const _SignOutOptionCard({
    required this.icon,
    required this.iconColor,
    required this.iconSurface,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconSurface;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return PressScale(
      onTap: onTap,
      child: ArenaCard(
        padding: const EdgeInsets.all(MedRashSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconSurface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: MedRashIconSize.md),
            ),
            const SizedBox(width: MedRashSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                  ),
                  const SizedBox(height: MedRashSpace.xs),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: MedRashSpace.sm),
            Icon(
              Icons.chevron_right_rounded,
              color: tokens.textSecondary,
              size: MedRashIconSize.md,
            ),
          ],
        ),
      ),
    );
  }
}
