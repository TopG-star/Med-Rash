import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:medrash_app/core/dev/component_catalog_page.dart';
import 'package:medrash_app/core/theme/app_theme.dart';

Widget _wrap() {
  final GoRouter router = GoRouter(
    initialLocation: '/start',
    routes: <RouteBase>[
      GoRoute(path: '/start', builder: (_, __) => const Placeholder()),
      GoRoute(
        path: '/catalog',
        builder: (_, __) => const ComponentCatalogPage(),
      ),
    ],
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => router.go('/catalog'));
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
  );
}

void main() {
  testWidgets('ComponentCatalogPage renders every primitive section',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (final String section in const <String>[
      'ArenaButton',
      'ArenaCard',
      'ArenaChip',
      'MonogramAvatar',
      'QuizProgressBar',
      'MedRashSkeleton',
      'MedRashEmptyState',
      'PressScale',
      'CountUpNumber',
      'StaggerList',
    ]) {
      expect(find.text(section), findsOneWidget,
          reason: 'Missing section: $section');
    }
  });

  testWidgets('ComponentCatalogPage swaps to dark preview when toggle is on',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final Finder switchFinder = find.byWidgetPredicate(
      (Widget w) =>
          w is Switch || w.runtimeType.toString() == 'CupertinoSwitch',
    );
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ArenaButton'), findsOneWidget);
  });
}
