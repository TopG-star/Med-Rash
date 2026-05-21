import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/events/medrash_events.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
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

  @override
  void initState() {
    super.initState();
    _profileRepository = getIt<ProfileRepository>();
    _loadProfile();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      return const ArenaScaffold(
        title: 'Profile',
        showBack: true,
        bottomNav: true,
        child: Center(child: CircularProgressIndicator()),
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
          ArenaCard(
            child: Column(
              children: <Widget>[
                const CircleAvatar(radius: 52, child: Icon(Icons.person, size: 44)),
                const SizedBox(height: 16),
                Text(
                  profile.fullName.trim().isEmpty ? profile.nickname : profile.fullName,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '@${profile.nickname}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                ArenaCard(
                  color: const Color(0xFFF7F7F7),
                  child: Column(
                    children: <Widget>[
                      Text('TOTAL POINTS', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 8),
                      Text('${profile.totalPoints}', style: Theme.of(context).textTheme.headlineLarge),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('NICKNAME', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          _ProfileField(controller: _nicknameController),
          const SizedBox(height: 20),
          Text('FACILITY', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          _ProfileField(controller: _facilityController),
          const SizedBox(height: 20),
          Text('SPECIALTY', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          ArenaCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: DropdownButtonFormField<String>(
              initialValue: _specialty,
              decoration: const InputDecoration(border: InputBorder.none),
              items: const <String>['Emergency Medicine', 'Pharmacy', 'General Practice']
                  .map(
                    (String value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _specialty = value;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          ArenaCard(
            color: const Color(0xFFFFD4E7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Secure Your Progress', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(
                  'Add an email or phone number to claim this account and save your rank across devices.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                const ArenaButton(
                  label: 'Claim Account',
                  icon: Icons.shield_outlined,
                  onPressed: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ArenaButton(
            label: 'Save Profile',
            onPressed: () async {
              final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
              final UserProfile updated = await _profileRepository.updateProfile(
                nickname: _nicknameController.text,
                facility: _facilityController.text,
                specialty: _specialty,
              );
              if (!mounted) {
                return;
              }
              setState(() {
                _profile = updated;
              });
              messenger.showSnackBar(
                const SnackBar(content: Text('Profile saved.')),
              );
            },
          ),
          const SizedBox(height: 24),
          ArenaCard(
            color: const Color(0xFFFCE4E4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Sign Out', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(
                  'Clear your profile from this device. Your leaderboard rank stays attached to whatever identity you sign in as next.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                ArenaButton(
                  label: 'Sign Out',
                  icon: Icons.logout,
                  onPressed: _showSignOutSheet,
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _showSignOutSheet() async {
    final _SignOutChoice? choice = await showModalBottomSheet<_SignOutChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final TextStyle? bodyStyle = Theme.of(sheetContext).textTheme.bodyMedium;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Sign out of MedRash?',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                ArenaButton(
                  label: 'Just sign me out on this device',
                  onPressed: () => Navigator.of(sheetContext).pop(_SignOutChoice.keepDevice),
                ),
                const SizedBox(height: 8),
                Text(
                  'You stay anonymous; signing back in with the same name puts you on the same leaderboard row.',
                  style: bodyStyle,
                ),
                const SizedBox(height: 20),
                ArenaButton(
                  label: 'Hand to someone else',
                  onPressed: () => Navigator.of(sheetContext).pop(_SignOutChoice.rotateDevice),
                ),
                const SizedBox(height: 8),
                Text(
                  'Treats this device as new. The next person joins as a separate leaderboard row.',
                  style: bodyStyle,
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
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

    await profileRepo.clearAll();
    await attemptStore.clearActive();
    await attemptStore.clearCompleted();
    await auth.signOut(keepDeviceId: keepDeviceId);
    eventBus.emit(IdentityResetEvent(keptDeviceId: keepDeviceId));

    if (!mounted) {
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Signed out.')));
    router.go('/join');
  }
}

enum _SignOutChoice { keepDevice, rotateDevice }

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ArenaCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }
}