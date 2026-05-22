import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../di/get_it.dart';
import '../infra/auth_state_manager.dart';
import 'guest_router.dart';
import 'user_router.dart';

/// Returns [next] only if it is a safe in-app path (starts with a single `/`).
/// Rejects null, scheme-relative (`//host`), and absolute URLs so a malicious
/// deep link like `/join?next=https://evil.test` cannot redirect users away
/// from the app after onboarding.
String? safeNextPath(String? next) {
  if (next == null || next.isEmpty) return null;
  if (!next.startsWith('/')) return null;
  if (next.startsWith('//')) return null;
  return next;
}

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
        // Preserve the original deep-link target (e.g. `/session/ABCD`) so
        // QuickJoinPage can return the user there after onboarding instead
        // of dumping them on /home.
        final String current = state.uri.toString();
        final String encoded = Uri.encodeComponent(current);
        return '/join?next=$encoded';
      }
      if (authStateManager.hasProfile && joining) {
        final String? next = safeNextPath(state.uri.queryParameters['next']);
        return next ?? '/home';
      }
      return null;
    },
    debugLogDiagnostics: kDebugMode,
  );
}