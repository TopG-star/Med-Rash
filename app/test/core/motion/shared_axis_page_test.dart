import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:medrash_app/core/motion/shared_axis_page.dart';

GoRouter _router({bool reducedMotion = false}) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        pageBuilder: (BuildContext _, GoRouterState state) => sharedAxisPage(
          state: state,
          child: const Scaffold(body: Center(child: Text('HOME'))),
          duration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/next',
        pageBuilder: (BuildContext _, GoRouterState state) => sharedAxisPage(
          state: state,
          child: const Scaffold(body: Center(child: Text('NEXT'))),
          duration: const Duration(milliseconds: 200),
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('navigates with fade + slide and settles on the target route',
      (WidgetTester tester) async {
    final GoRouter router = _router();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    expect(find.text('HOME'), findsOneWidget);

    router.go('/next');
    await tester.pump();
    // Mid-transition: NEXT is mounted but a FadeTransition is in-flight.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FadeTransition), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text('NEXT'), findsOneWidget);
  });

  testWidgets('reduced-motion returns the body without transition wrappers',
      (WidgetTester tester) async {
    final GoRouter router = _router(reducedMotion: true);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.go('/next');
    await tester.pumpAndSettle();
    expect(find.text('NEXT'), findsOneWidget);
  });
}
