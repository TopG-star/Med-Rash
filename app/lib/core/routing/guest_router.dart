import 'package:go_router/go_router.dart';

import '../../features/profile/screens/quick_join_page.dart';
import 'app_router.dart';

List<RouteBase> buildGuestRoutes() {
  return <RouteBase>[
    GoRoute(
      path: '/join',
      builder: (_, GoRouterState state) => QuickJoinPage(
        nextPath: safeNextPath(state.uri.queryParameters['next']),
      ),
    ),
  ];
}