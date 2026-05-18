import 'package:go_router/go_router.dart';

import '../../features/profile/screens/quick_join_page.dart';

List<RouteBase> buildGuestRoutes() {
  return <RouteBase>[
    GoRoute(
      path: '/join',
      builder: (_, __) => const QuickJoinPage(),
    ),
  ];
}