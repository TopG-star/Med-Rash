import 'package:go_router/go_router.dart';

import '../../features/profile/screens/quick_join_page.dart';
import '../../features/profile/screens/recovery_page.dart';
import 'app_router.dart';
import '../motion/shared_axis_page.dart';

List<RouteBase> buildGuestRoutes() {
  return <RouteBase>[
    GoRoute(
      path: '/join',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: QuickJoinPage(
          nextPath: safeNextPath(state.uri.queryParameters['next']),
        ),
      ),
    ),
    GoRoute(
      path: '/recover',
      pageBuilder: (_, GoRouterState state) => sharedAxisPage<void>(
        state: state,
        child: const RecoveryPage(),
      ),
    ),
  ];
}