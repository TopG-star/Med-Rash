import 'package:flutter/material.dart';

import '../../../core/di/get_it.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
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
      child: ListView(
        children: <Widget>[
          ArenaCard(
            child: Column(
              children: <Widget>[
                const CircleAvatar(radius: 52, child: Icon(Icons.person, size: 44)),
                const SizedBox(height: 16),
                Text(profile.nickname, style: Theme.of(context).textTheme.headlineMedium),
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
              value: _specialty,
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
        ],
      ),
    );
  }
}

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