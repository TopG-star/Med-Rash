/// Pure decision function for the app-wide auth redirect. Lives in its own
/// file so it can be unit-tested without spinning up GoRouter or the DI
/// container.
///
/// Three outcomes:
/// * `path != null` — caller should redirect to that path.
/// * `fastJoin == true` — caller should mint a guest profile in place and
///   then leave navigation alone (returns null after the side effect).
/// * everything default — caller should stay on the current route.
class AuthRedirectDecision {
  const AuthRedirectDecision({this.path, this.fastJoin = false});

  final String? path;
  final bool fastJoin;

  bool get stay => path == null && !fastJoin;
}

bool _isSessionPath(String matchedLocation) {
  return matchedLocation == '/session' || matchedLocation.startsWith('/session/');
}

/// See [AuthRedirectDecision] for outcomes. [safeNext] is the policy that
/// trims open-redirect attempts on the post-onboarding hop; pass
/// [safeNextPath] from `app_router.dart`.
AuthRedirectDecision computeAuthRedirect({
  required bool hasProfile,
  required String matchedLocation,
  required String currentUri,
  required String? nextParam,
  required bool fastJoinEnabled,
  required String? Function(String?) safeNext,
}) {
  final bool joining = matchedLocation == '/join';
  if (!hasProfile && !joining) {
    if (fastJoinEnabled && _isSessionPath(matchedLocation)) {
      return const AuthRedirectDecision(fastJoin: true);
    }
    final String encoded = Uri.encodeComponent(currentUri);
    return AuthRedirectDecision(path: '/join?next=$encoded');
  }
  if (hasProfile && joining) {
    return AuthRedirectDecision(path: safeNext(nextParam) ?? '/home');
  }
  return const AuthRedirectDecision();
}
