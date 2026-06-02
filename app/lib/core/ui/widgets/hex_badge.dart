import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// Hexagonal badge container used for achievement glyphs, rank emblems, and
/// status indicators throughout the gamified surfaces. Clips its child to a
/// pointy-top hexagon and overlays a colored border so the silhouette reads
/// cleanly on busy backgrounds.
class HexBadge extends StatelessWidget {
  const HexBadge({
    super.key,
    required this.child,
    this.size = 56,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 2,
  });

  final Widget child;
  final double size;
  final Color? fillColor;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color fill = fillColor ?? tokens.secondary;
    final Color border = borderColor ?? tokens.outline;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HexBorderPainter(
          fillColor: fill,
          borderColor: border,
          borderWidth: borderWidth,
        ),
        child: ClipPath(
          clipper: const _HexClipper(),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  const _HexClipper();

  @override
  Path getClip(Size size) => _hexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _HexBorderPainter extends CustomPainter {
  const _HexBorderPainter({
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
  });

  final Color fillColor;
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = _hexPath(size);
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HexBorderPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}

/// Pointy-top hexagon (vertex at 12 o'clock). Inscribed in the given size.
Path _hexPath(Size size) {
  final double w = size.width;
  final double h = size.height;
  final double cx = w / 2;
  final double cy = h / 2;
  final double r = math.min(w, h) / 2;
  final Path path = Path();
  for (int i = 0; i < 6; i++) {
    // Pointy-top: rotate by -90deg so vertex 0 is at the top.
    final double angle = (math.pi / 3) * i - math.pi / 2;
    final double x = cx + r * math.cos(angle);
    final double y = cy + r * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}
