import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/get_it.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/identity_badge.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../../session/events/last_session_recorded_event.dart';
import '../../session/storage/last_session_store.dart';

/// Front-door landing page introduced in Slice 2a of the QR-deep-link
/// workstream. Surfaces three primary entry points (Live / Ranked / Learn)
/// plus a "Continue last session" smart-default card driven by
/// [LastSessionStore]. The Explore link preserves the previous full-feed UX
/// for users who want to browse the whole catalog.
class ModeSelectionPage extends StatefulWidget {
  const ModeSelectionPage({super.key});

  @override
  State<ModeSelectionPage> createState() => _ModeSelectionPageState();
}

class _ModeSelectionPageState extends State<ModeSelectionPage> {
  late final LastSessionStore _lastSessionStore;
  late final EventBus _eventBus;
  StreamSubscription<LastSessionRecordedEvent>? _lastSessionSubscription;
  LastSessionRecord? _lastSession;

  @override
  void initState() {
    super.initState();
    _lastSessionStore = getIt<LastSessionStore>();
    _eventBus = getIt<EventBus>();
    _refreshLastSession();
    _lastSessionSubscription = _eventBus
        .on<LastSessionRecordedEvent>()
        .listen((_) => _refreshLastSession());
  }

  @override
  void dispose() {
    _lastSessionSubscription?.cancel();
    super.dispose();
  }

  void _refreshLastSession() {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastSession = _lastSessionStore.read();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ArenaScaffold(
      title: MedRashStrings.appTitle,
      bottomNav: true,
      actions: const <Widget>[IdentityBadge()],
      child: ListView(
        children: <Widget>[
          Text(
            MedRashStrings.modeSelectionIntro,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (_lastSession != null) ...<Widget>[
            _ContinueLastSessionCard(record: _lastSession!),
            const SizedBox(height: 24),
          ],
          _ModeCard(
            label: MedRashStrings.modeLiveLabel,
            description: MedRashStrings.modeLiveDescription,
            icon: Icons.podcasts_outlined,
            onTap: () => context.go('/live'),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            label: MedRashStrings.modeRankedLabel,
            description: MedRashStrings.modeRankedDescription,
            icon: Icons.workspace_premium_outlined,
            onTap: () => context.go('/ranked'),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            label: MedRashStrings.modeLearnLabel,
            description: MedRashStrings.modeLearnDescription,
            icon: Icons.menu_book_outlined,
            onTap: () => context.go('/learn'),
          ),
          const SizedBox(height: 32),
          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/explore'),
              icon: const Icon(Icons.travel_explore_outlined),
              label: const Text(MedRashStrings.exploreCta),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueLastSessionCard extends StatelessWidget {
  const _ContinueLastSessionCard({required this.record});

  final LastSessionRecord record;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String agoLabel = _formatAgo(DateTime.now().difference(record.openedAt));
    return ArenaCard(
      color: tokens.warningSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.history_outlined, color: tokens.outline),
              const SizedBox(width: 12),
              Text(
                MedRashStrings.continueLastSessionTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Code ${record.joinCode} \u2022 opened $agoLabel.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ArenaButton(
            label: MedRashStrings.continueLastSessionCta,
            icon: Icons.play_arrow_outlined,
            onPressed: () =>
                context.go('/session/${Uri.encodeComponent(record.joinCode)}'),
          ),
        ],
      ),
    );
  }

  String _formatAgo(Duration diff) {
    if (diff.inSeconds < 60) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      final int m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    final int h = diff.inHours;
    final int m = diff.inMinutes - h * 60;
    if (m == 0) {
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    return '${h}h ${m}m ago';
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusLarge),
      child: ArenaCard(
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.primary,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(color: tokens.outline, width: tokens.borderWidth),
              ),
              child: Icon(icon, color: tokens.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(description, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: tokens.outline),
          ],
        ),
      ),
    );
  }
}
