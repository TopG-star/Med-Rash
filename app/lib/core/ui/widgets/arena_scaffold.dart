import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_extensions.dart';
import 'arena_bottom_nav.dart';

class ArenaScaffold extends StatelessWidget {
  const ArenaScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBack = false,
    this.showClose = false,
    this.bottomNav = false,
  });

  final String title;
  final Widget child;
  final bool showBack;
  final bool showClose;
  final bool bottomNav;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final String location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      appBar: AppBar(
        title: Text(title.toUpperCase()),
        leading: showBack || showClose
            ? IconButton(
                onPressed: () => context.pop(),
                icon: Icon(showClose ? Icons.close : Icons.arrow_back),
              )
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(color: tokens.outline, height: 3),
        ),
      ),
      bottomNavigationBar: bottomNav ? ArenaBottomNav(location: location) : null,
      body: Container(
        decoration: BoxDecoration(
          color: tokens.background,
          image: DecorationImage(
            image: const AssetImage(''),
            onError: (_, __) {},
          ),
        ),
        child: CustomPaint(
          painter: _DotGridPainter(color: tokens.outlineMuted),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(tokens.pageMargin),
              child: child,
            ),
          ),
        ),
      ),
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