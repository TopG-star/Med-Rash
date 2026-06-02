import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/bottom_nav_with_fab.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(bottomNavigationBar: child, body: const SizedBox()),
  );
}

void main() {
  group('BottomNavWithFab', () {
    testWidgets('renders all tab labels and FAB icon', (tester) async {
      await tester.pumpWidget(_host(BottomNavWithFab(
        items: const <BottomNavItem>[
          BottomNavItem(icon: Icons.home_rounded, label: 'Home'),
          BottomNavItem(icon: Icons.add_rounded, isFab: true),
          BottomNavItem(icon: Icons.person_rounded, label: 'Profile'),
        ],
        currentIndex: 0,
        onTap: (_) {},
        onFabTap: () {},
      )));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('tapping a tab fires onTap with its index', (tester) async {
      int? lastIndex;
      await tester.pumpWidget(_host(BottomNavWithFab(
        items: const <BottomNavItem>[
          BottomNavItem(icon: Icons.home_rounded, label: 'Home'),
          BottomNavItem(icon: Icons.add_rounded, isFab: true),
          BottomNavItem(icon: Icons.person_rounded, label: 'Profile'),
        ],
        currentIndex: 0,
        onTap: (int i) => lastIndex = i,
        onFabTap: () {},
      )));
      await tester.tap(find.text('Profile'));
      await tester.pump();
      expect(lastIndex, 2);
    });

    testWidgets('tapping the FAB fires onFabTap (not onTap)', (tester) async {
      int taps = 0;
      int fabTaps = 0;
      await tester.pumpWidget(_host(BottomNavWithFab(
        items: const <BottomNavItem>[
          BottomNavItem(icon: Icons.home_rounded, label: 'Home'),
          BottomNavItem(icon: Icons.add_rounded, isFab: true),
        ],
        currentIndex: 0,
        onTap: (_) => taps++,
        onFabTap: () => fabTaps++,
      )));
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(fabTaps, 1);
      expect(taps, 0);
    });

    testWidgets('asserts when no item has isFab: true', (tester) async {
      await tester.pumpWidget(_host(BottomNavWithFab(
        items: const <BottomNavItem>[
          BottomNavItem(icon: Icons.home_rounded, label: 'Home'),
        ],
        currentIndex: 0,
        onTap: (_) {},
        onFabTap: () {},
      )));
      expect(tester.takeException(), isA<AssertionError>());
    });
  });
}
