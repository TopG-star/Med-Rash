import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_extensions.dart';
import '../../../features/quiz/screens/qr_scanner_page.dart';
import 'bottom_nav_with_fab.dart';
import 'gradient_card.dart';
import 'hex_badge.dart';

/// Global bottom chrome. Wraps [BottomNavWithFab] with go_router-driven
/// navigation and a centered Quick Actions FAB that opens a bottom sheet
/// with "Scan QR" + "Enter code" (the two live-session entry points).
///
/// Index layout (FAB is index 2 and reserved):
/// 0 Home  •  1 Rank  •  [2 FAB]  •  3 Explore  •  4 Profile
class MedRashBottomNav extends StatelessWidget {
  const MedRashBottomNav({super.key, required this.location});

  final String location;

  int _selectedIndex() {
    if (location.startsWith('/leaderboard')) {
      return 1;
    }
    if (location.startsWith('/explore') ||
        location.startsWith('/quiz-detail') ||
        location.startsWith('/learn') ||
        location.startsWith('/ranked') ||
        location.startsWith('/academy')) {
      return 3;
    }
    if (location.startsWith('/profile')) {
      return 4;
    }
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/leaderboard');
      case 3:
        context.go('/explore');
      case 4:
        context.go('/profile');
    }
  }

  Future<void> _openQuickActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) => _QuickActionsSheet(rootContext: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavWithFab(
      currentIndex: _selectedIndex(),
      onTap: (int i) => _onTap(context, i),
      onFabTap: () => _openQuickActions(context),
      items: const <BottomNavItem>[
        BottomNavItem(icon: Icons.home_rounded, label: 'Home'),
        BottomNavItem(icon: Icons.bar_chart_rounded, label: 'Rank'),
        BottomNavItem(icon: Icons.bolt_rounded, isFab: true),
        BottomNavItem(icon: Icons.travel_explore_rounded, label: 'Explore'),
        BottomNavItem(icon: Icons.person_rounded, label: 'Profile'),
      ],
    );
  }
}

class _QuickActionsSheet extends StatelessWidget {
  const _QuickActionsSheet({required this.rootContext});

  /// The page-level context. Used for go_router navigation AFTER the sheet
  /// pops, so we don't try to navigate from a context whose Router ancestor
  /// is about to be torn down.
  final BuildContext rootContext;

  Future<void> _onScanQr(BuildContext sheetCtx) async {
    Navigator.of(sheetCtx).pop();
    final String? code = await Navigator.of(rootContext).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const QrScannerPage(),
        fullscreenDialog: true,
      ),
    );
    if (code == null || code.isEmpty) return;
    if (!rootContext.mounted) return;
    rootContext.go('/session/${Uri.encodeComponent(code)}');
  }

  void _onEnterCode(BuildContext sheetCtx) {
    Navigator.of(sheetCtx).pop();
    if (!rootContext.mounted) return;
    rootContext.go('/live');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Quick actions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            _QuickActionTile(
              icon: Icons.qr_code_scanner_rounded,
              accent: tokens.primary,
              accentSoft: tokens.primarySoft,
              surface: tokens.cardLavender,
              title: 'Scan QR',
              subtitle: 'Join a live session with your camera',
              onTap: () => _onScanQr(context),
            ),
            const SizedBox(height: 12),
            _QuickActionTile(
              icon: Icons.dialpad_rounded,
              accent: tokens.onSecondary,
              accentSoft: tokens.secondary,
              surface: tokens.cardGold,
              title: 'Enter code',
              subtitle: 'Type a 4–6 char join code',
              onTap: () => _onEnterCode(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.accent,
    required this.accentSoft,
    required this.surface,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final Color accentSoft;
  final Color surface;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return GradientCard(
      color: surface,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          HexBadge(
            size: 48,
            fillColor: accentSoft,
            borderColor: accent,
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: tokens.textSecondary),
        ],
      ),
    );
  }
}
