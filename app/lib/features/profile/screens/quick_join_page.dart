import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/identity_snapshot.dart';
import '../../../core/ui/operation_runner_state.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/theme/theme_extensions.dart';
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

  Future<void> _resumeSnapshot(IdentitySnapshot snapshot) async {
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final IdentitySnapshot? snapshot = _authStateManager.lastSignedOutSnapshot;

    return ArenaScaffold(
      title: 'Join The Academy',
      showBack: false,
      child: MedRashConstrainedBody(
        child: ListView(
        children: <Widget>[
          if (snapshot != null) ...<Widget>[
            _ResumeCard(
              snapshot: snapshot,
              onResume: () => _resumeSnapshot(snapshot),
              onStartFresh: _startFresh,
            ),
            const SizedBox(height: 28),
          ],
          Text('FULL NAME', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          _ArenaTextField(
            controller: _nameController,
            hintText: 'Enter your full name',
            onChanged: (String value) {
              setState(() {
                if (value.trim().isNotEmpty) {
                  _nickname = _profileRepository.generateNickname(fullName: value);
                }
              });
            },
          ),
          const SizedBox(height: 20),
          Text('FACILITY', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          _ArenaTextField(
            controller: _facilityController,
            hintText: 'e.g. Korle-Bu Teaching Hospital',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text('SPECIALTY', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          ArenaCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: DropdownButtonFormField<String>(
              // Netlify build pins Flutter 3.27.4 where `initialValue` doesn't exist yet.
              // ignore: deprecated_member_use
              value: _specialty,
              decoration: const InputDecoration(border: InputBorder.none),
              items: const <String>['Doctor', 'Pharmacist', 'Nurse', 'Medical Rep']
                  .map(
                    (String value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _specialty = value;
                });
              },
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'YOUR AUTO-GENERATED TAG',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          ArenaCard(
            color: tokens.secondary,
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 28,
                  backgroundColor: tokens.primary,
                  child: const Icon(Icons.person, color: Colors.black),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _nickname,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ready for the leaderboard',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _nickname = _profileRepository.generateNickname(
                        fullName: _nameController.text,
                      );
                    });
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ArenaButton(
            label: 'Start Playing',
            onPressed: _canStart
                ? () async {
                    await runOperation(() async {
                      await _profileRepository.quickJoin(
                        fullName: _nameController.text,
                        facility: _facilityController.text,
                        specialty: _specialty,
                        nickname: _nickname,
                      );
                      await getIt<AuthStateManager>().markJoined();
                    });
                    if (context.mounted) {
                      context.go(widget.nextPath ?? '/home');
                    }
                  }
                : null,
          ),
        ],
        ),
      ),
    );
  }

  bool get _canStart {
    return _nameController.text.trim().isNotEmpty &&
        _facilityController.text.trim().isNotEmpty;
  }
}

class _ArenaTextField extends StatelessWidget {
  const _ArenaTextField({
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return ArenaCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
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

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.snapshot,
    required this.onResume,
    required this.onStartFresh,
  });

  final IdentitySnapshot snapshot;
  final VoidCallback onResume;
  final VoidCallback onStartFresh;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaCard(
      color: tokens.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: tokens.primary,
                child: const Icon(Icons.person, color: Colors.black),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'WELCOME BACK',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snapshot.nickname.isNotEmpty
                          ? snapshot.nickname
                          : 'Returning player',
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (snapshot.facility.isNotEmpty)
                      Text(
                        snapshot.facility,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ArenaButton(
            label: 'Continue as ${snapshot.nickname.isNotEmpty ? snapshot.nickname : "previous player"}',
            onPressed: onResume,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onStartFresh,
            child: const Text('Not you? Start fresh'),
          ),
        ],
      ),
    );
  }
}