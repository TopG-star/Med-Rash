import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../dev/component_catalog_page.dart';
import '../motion/shared_axis_page.dart';
import '../../features/badges/screens/badges_page.dart';
import '../../features/leaderboard/screens/world_rank_page.dart';
import '../../features/leaderboard/screens/session_live_leaderboard_page.dart';
import '../../features/profile/screens/profile_page.dart';
import '../../features/quiz/models/quiz_detail_launch.dart';
import '../../features/quiz/screens/explore_page.dart';
import '../../features/quiz/screens/learn_page.dart';
import '../../features/quiz/screens/live_page.dart';
import '../../features/quiz/screens/mode_selection_page.dart';
import '../../features/quiz/screens/quiz_detail_page.dart';
import '../../features/quiz/screens/quiz_result_page.dart';
import '../../features/quiz/screens/quiz_runner_page.dart';
import '../../features/quiz/screens/ranked_page.dart';
import '../../features/session/screens/session_join_page.dart';

List<RouteBase> buildUserRoutes() {
  return <RouteBase>[
    GoRoute(
      path: '/home',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const ModeSelectionPage(),
      ),
    ),
    GoRoute(
      path: '/explore',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const ExplorePage(),
      ),
    ),
    GoRoute(
      path: '/live',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const LivePage(),
      ),
    ),
    GoRoute(
      path: '/ranked',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const RankedPage(),
      ),
    ),
    GoRoute(
      path: '/learn',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const LearnPage(),
      ),
    ),
    GoRoute(
      path: '/quiz-detail',
      pageBuilder: (_, GoRouterState state) {
        final QuizDetailLaunch launch =
            QuizDetailLaunch.fromExtra(state.extra);
        return sharedAxisPage<void>(
          state: state,
          child: QuizDetailPage(
            quizId: launch.quizId,
            preselectedMode: launch.preselectedMode,
          ),
        );
      },
    ),
    // Backcompat alias for any in-flight `/academy` links. The bottom nav
    // and all internal callers were migrated to `/quiz-detail` in Slice 2a.
    GoRoute(
      path: '/academy',
      redirect: (_, __) => '/quiz-detail',
    ),
    GoRoute(
      path: '/session',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: SessionJoinPage(
          joinCode: state.uri.queryParameters['joinCode'] ?? state.uri.queryParameters['code'],
        ),
      ),
    ),
    GoRoute(
      path: '/session/:joinCode',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: SessionJoinPage(
          joinCode: state.pathParameters['joinCode'],
        ),
      ),
    ),
    GoRoute(
      path: '/quiz',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const QuizRunnerPage(),
      ),
    ),
    GoRoute(
      path: '/result',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const QuizResultPage(),
      ),
    ),
    GoRoute(
      path: '/leaderboard',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const WorldRankPage(),
      ),
    ),
    GoRoute(
      path: '/session-leaderboard/:sessionId',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: SessionLiveLeaderboardPage(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const ProfilePage(),
      ),
    ),
    GoRoute(
      path: '/badges',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const BadgesPage(),
      ),
    ),
    if (!kReleaseMode)
      GoRoute(
        path: '/dev/catalog',
        pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
          state: state,
          child: const ComponentCatalogPage(),
        ),
      ),
  ];
}