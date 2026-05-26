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
      indicatorColor: tokens.primary,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      destinations: const <NavigationDestination>[
        NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Rank'),
        NavigationDestination(icon: Icon(Icons.travel_explore_rounded), label: 'Explore'),
        NavigationDestination(icon: Icon(Icons.person_rounded), label: 'Profile'),
      ],
    );
  }
}