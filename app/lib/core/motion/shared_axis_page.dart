import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../theme/arena_motion.dart';

/// Shared-axis (horizontal) transition page factory for go_router. Replaces
/// the platform-default slide with a softer fade + slight axis translation
/// that matches the Vibrant Pulse motion vocabulary.
///
/// Usage:
/// ```dart
/// GoRoute(
///   path: '/profile',
///   pageBuilder: (ctx, state) => sharedAxisPage(
///     state: state,
///     child: const ProfilePage(),
///   ),
/// );
/// ```
CustomTransitionPage<T> sharedAxisPage<T>({
  required GoRouterState state,
  required Widget child,
  Duration? duration,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration ?? ArenaMotion.medium,
    reverseTransitionDuration: duration ?? ArenaMotion.medium,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondary,
      Widget body,
    ) {
      final bool reduced =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduced) return body;

      final Animation<double> fadeIn = CurvedAnimation(
        parent: animation,
        curve: ArenaMotion.standard,
      );
      final Animation<Offset> slideIn = Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(fadeIn);

      final Animation<double> fadeOut = CurvedAnimation(
        parent: secondary,
        curve: ArenaMotion.standard,
      );
      final Animation<Offset> slideOut = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.04, 0),
      ).animate(fadeOut);

      return FadeTransition(
        opacity: fadeIn,
        child: SlideTransition(
          position: slideIn,
          child: SlideTransition(
            position: slideOut,
            child: FadeTransition(
              opacity: ReverseAnimation(fadeOut),
              child: body,
            ),
          ),
        ),
      );
    },
  );
}
