import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/identity_snapshot.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/ui/operation_runner_state.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../session/storage/last_session_store.dart';
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
  String? _pendingJoinCode;

  @override
  void initState() {
    super.initState();
    _profileRepository = getIt<ProfileRepository>();
    _authStateManager = getIt<AuthStateManager>();
    _nickname = _profileRepository.generateNickname();
    _authStateManager.addListener(_onAuthChanged);
    // Capture QR-borne joinCode immediately so a router race or a lost
    // `nextPath` (e.g. SPA fallback dropping the deep link) cannot orphan
    // the participant on Mode Selection without a way back to their session.
    _pendingJoinCode = joinCodeFromNextPath(widget.nextPath);
    final String? code = _pendingJoinCode;
    if (code != null) {
      // Fire-and-forget: a write failure here must not block onboarding.
      unawaited(getIt<LastSessionStore>().record(code));
    }
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
    final String? joiningCode = joinCodeFromNextPath(widget.nextPath);

    return ArenaScaffold(
      title: 'Join The Academy',
      showBack: false,
      child: MedRashConstrainedBody(
        child: ListView(
        children: <Widget>[
          if (joiningCode != null) ...<Widget>[
            _SessionContextCard(joinCode: joiningCode),
            const SizedBox(height: 20),
          ],
          if (snapshot != null) ...<Widget>[
            _ResumeCard(
              snapshot: snapshot,
              joiningCode: joiningCode,
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
            label: joiningCode != null
                ? 'Continue to session $joiningCode'
                : 'Start Playing',
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
                      context.go(_postOnboardingDestination());
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

  /// Pick the post-onboarding hop. Order of preference:
  ///   1. QR joinCode captured at page-build time → `/session/<code>` directly.
  ///      Defensive against `widget.nextPath` getting nulled by a router
  ///      race (e.g. listenable refresh from `markJoined()` before our
  ///      explicit `context.go`).
  ///   2. The raw sanitized `nextPath` we were handed.
  ///   3. Mode Selection home as the final fallback.
  String _postOnboardingDestination() {
    final String? code = _pendingJoinCode;
    if (code != null && code.isNotEmpty) {
      return '/session/${Uri.encodeComponent(code)}';
    }
    return widget.nextPath ?? '/home';
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
            label: _resumeLabel(),
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
      color: tokens.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.qr_code_2, color: Colors.black),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You're joining session $joinCode",
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Choose a nickname and you'll join the session right after.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}