import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/arena_scaffold.dart';

Widget _wrap({required bool showBack, required bool showClose}) {
  final GoRouter router = GoRouter(
    initialLocation: '/start',
    routes: <RouteBase>[
      GoRoute(path: '/start', builder: (_, __) => const Placeholder()),
      GoRoute(
        path: '/target',
        builder: (_, __) => ArenaScaffold(
          title: 'Screen',
          showBack: showBack,
          showClose: showClose,
          child: const SizedBox.shrink(),
        ),
      ),
    ],
  );
  // Kick navigation so the target route renders.
  WidgetsBinding.instance.addPostFrameCallback((_) => router.go('/target'));
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
  );
}

void main() {
  group('Semantics labels - icon-only navigation', () {
    testWidgets('ArenaScaffold back button exposes a tooltip', (tester) async {
      await tester.pumpWidget(_wrap(showBack: true, showClose: false));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('ArenaScaffold close button exposes a tooltip', (tester) async {
      await tester.pumpWidget(_wrap(showBack: false, showClose: true));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget);
    });
  });
}
