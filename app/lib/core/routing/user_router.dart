import 'package:go_router/go_router.dart';

import '../../features/leaderboard/screens/world_rank_page.dart';
import '../../features/profile/screens/profile_page.dart';
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
      builder: (_, __) => const ModeSelectionPage(),
    ),
    GoRoute(
      path: '/explore',
      builder: (_, __) => const ExplorePage(),
    ),
    GoRoute(
      path: '/live',
      builder: (_, __) => const LivePage(),
    ),
    GoRoute(
      path: '/ranked',
      builder: (_, __) => const RankedPage(),
    ),
    GoRoute(
      path: '/learn',
      builder: (_, __) => const LearnPage(),
    ),
    GoRoute(
      path: '/quiz-detail',
      builder: (_, GoRouterState state) => QuizDetailPage(
        quizId: state.extra is String ? state.extra as String : null,
      ),
    ),
    // Backcompat alias for any in-flight `/academy` links. The bottom nav
    // and all internal callers were migrated to `/quiz-detail` in Slice 2a.
    GoRoute(
      path: '/academy',
      redirect: (_, __) => '/quiz-detail',
    ),
    GoRoute(
      path: '/session',
      builder: (_, GoRouterState state) => SessionJoinPage(
        joinCode: state.uri.queryParameters['joinCode'] ?? state.uri.queryParameters['code'],
      ),
    ),
    GoRoute(
      path: '/session/:joinCode',
      builder: (_, GoRouterState state) => SessionJoinPage(
        joinCode: state.pathParameters['joinCode'],
      ),
    ),
    GoRoute(
      path: '/quiz',
      builder: (_, __) => const QuizRunnerPage(),
    ),
    GoRoute(
      path: '/result',
      builder: (_, __) => const QuizResultPage(),
    ),
    GoRoute(
      path: '/leaderboard',
      builder: (_, __) => const WorldRankPage(),
    ),
    GoRoute(
      path: '/profile',
      builder: (_, __) => const ProfilePage(),
    ),
  ];
}