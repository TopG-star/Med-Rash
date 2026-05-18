import 'package:flutter/material.dart';

import '../di/get_it.dart';
import '../infra/overlay_manager.dart';
import '../routing/app_router.dart';
import '../theme/app_theme.dart';

class ArenaApp extends StatelessWidget {
  const ArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final OverlayController overlayController = getIt<OverlayController>();
    final router = buildRouter();

    return MaterialApp.router(
      title: 'MedRash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        return OverlayManager(
          controller: overlayController,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}
