import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_extensions.dart';

class ArenaBottomNav extends StatelessWidget {
  const ArenaBottomNav({super.key, required this.location});

  final String location;

  int _selectedIndex() {
    if (location.startsWith('/leaderboard')) {
      return 1;
    }
    if (location.startsWith('/explore') ||
        location.startsWith('/quiz-detail') ||
        location.startsWith('/academy')) {
      return 2;
    }
    if (location.startsWith('/profile')) {
      return 3;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return NavigationBar(
      selectedIndex: _selectedIndex(),
      onDestinationSelected: (int index) {
        switch (index) {
          case 0:
            context.go('/home');
          case 1:
            context.go('/leaderboard');
          case 2:
            context.go('/explore');
          case 3:
            context.go('/profile');
        }
      },
      backgroundColor: tokens.surface,
      indicatorColor: tokens.primarySoft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      destinations: <NavigationDestination>[
        NavigationDestination(
          icon: const Icon(Icons.home_rounded),
          selectedIcon: Icon(Icons.home_rounded, color: tokens.primary),
          label: 'Home',
        ),
        NavigationDestination(
          icon: const Icon(Icons.bar_chart_rounded),
          selectedIcon: Icon(Icons.bar_chart_rounded, color: tokens.primary),
          label: 'Rank',
        ),
        NavigationDestination(
          icon: const Icon(Icons.travel_explore_rounded),
          selectedIcon:
              Icon(Icons.travel_explore_rounded, color: tokens.primary),
          label: 'Explore',
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_rounded),
          selectedIcon: Icon(Icons.person_rounded, color: tokens.primary),
          label: 'Profile',
        ),
      ],
    );
  }
}