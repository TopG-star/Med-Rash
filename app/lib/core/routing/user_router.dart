import 'package:go_router/go_router.dart';

import '../../features/leaderboard/screens/world_rank_page.dart';
import '../../features/profile/screens/profile_page.dart';
import '../../features/quiz/screens/home_page.dart';
import '../../features/quiz/screens/quiz_detail_page.dart';
import '../../features/quiz/screens/quiz_result_page.dart';
import '../../features/quiz/screens/quiz_runner_page.dart';
import '../../features/session/screens/session_join_page.dart';

List<RouteBase> buildUserRoutes() {
  return <RouteBase>[
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomePage(),
    ),
    GoRoute(
      path: '/academy',
      builder: (_, GoRouterState state) => QuizDetailPage(
        quizId: state.extra is String ? state.extra as String : null,
      ),
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