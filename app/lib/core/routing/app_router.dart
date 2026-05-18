import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../di/get_it.dart';
import '../infra/auth_state_manager.dart';
import 'guest_router.dart';
import 'user_router.dart';

GoRouter buildRouter() {
  final AuthStateManager authStateManager = getIt<AuthStateManager>();

  return GoRouter(
    initialLocation: authStateManager.hasProfile ? '/home' : '/join',
    refreshListenable: authStateManager,
    routes: <RouteBase>[
      ...buildGuestRoutes(),
      ...buildUserRoutes(),
    ],
    redirect: (_, GoRouterState state) {
      final bool joining = state.matchedLocation == '/join';
      if (!authStateManager.hasProfile && !joining) {
        return '/join';
      }
      if (authStateManager.hasProfile && joining) {
        return '/home';
      }
      return null;
    },
    debugLogDiagnostics: kDebugMode,
  );
}