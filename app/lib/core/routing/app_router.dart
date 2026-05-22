import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../di/get_it.dart';
import '../infra/auth_state_manager.dart';
import '../../features/profile/repositories/profile_repository.dart';
import 'auth_redirect.dart';
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
    redirect: (_, GoRouterState state) async {
      final AuthRedirectDecision decision = computeAuthRedirect(
        hasProfile: authStateManager.hasProfile,
        matchedLocation: state.matchedLocation,
        currentUri: state.uri.toString(),
        nextParam: state.uri.queryParameters['next'],
        fastJoinEnabled: AppConfig.qrFastJoin,
        safeNext: safeNextPath,
      );
      if (decision.fastJoin) {
        await getIt<ProfileRepository>().mintGuestProfile();
        await authStateManager.markJoined();
        return null;
      }
      return decision.path;
    },
    debugLogDiagnostics: kDebugMode,
  );
}