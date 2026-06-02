import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_extensions.dart';
import 'medrash_bottom_nav.dart';

class ArenaScaffold extends StatelessWidget {
  const ArenaScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBack = false,
    this.showClose = false,
    this.bottomNav = false,
    this.actions,
    this.fallbackRoute = '/home',
  });

  final String title;
  final Widget child;
  final bool showBack;
  final bool showClose;
  final bool bottomNav;
  final List<Widget>? actions;

  /// Route to navigate to when the user requests back/close (app bar leading
  /// button or OS gesture) but no entry exists on the navigation stack —
  /// e.g. deep-link cold start. Defaults to `/home`. Set explicitly on guest
  /// surfaces that should bounce to a different anchor.
  final String fallbackRoute;

  /// Safe back/close handler shared by the app bar leading button and the
  /// PopScope OS-gesture interceptor. Pops if there is somewhere to pop to,
  /// otherwise navigates to [fallbackRoute] so the user is never stuck.
  void _safeBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String location = GoRouterState.of(context).matchedLocation;
    final bool canRouterPop = context.canPop();

    return PopScope<Object?>(
      canPop: canRouterPop,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        context.go(fallbackRoute);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title.toUpperCase()),
          leading: showBack || showClose
              ? IconButton(
                  tooltip: showClose ? 'Close' : 'Back',
                  onPressed: () => _safeBack(context),
                  icon: Icon(
                    showClose ? Icons.close_rounded : Icons.arrow_back_rounded,
                  ),
                )
              : null,
          actions: actions,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: Container(color: tokens.outline, height: 3),
          ),
        ),
        bottomNavigationBar:
            bottomNav ? MedRashBottomNav(location: location) : null,
        body: CustomPaint(
          painter: _DotGridPainter(color: tokens.outlineMuted),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(tokens.pageMargin),
              child: ScrollConfiguration(
                behavior: const _ThinScrollBehavior(),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinScrollBehavior extends ScrollBehavior {
  const _ThinScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thickness: 4,
      radius: const Radius.circular(8),
      thumbVisibility: false,
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color.withValues(alpha: 0.6);
    for (double x = 0; x < size.width; x += 16) {
      for (double y = 0; y < size.height; y += 16) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}