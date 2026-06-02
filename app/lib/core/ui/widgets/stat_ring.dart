import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// Circular progress ring used for Stats / completion summaries (e.g. the
/// "37/50" hero ring on the Profile and Stats surfaces). Renders an unfilled
/// track + a filled arc starting at 12 o'clock and sweeping clockwise. The
/// optional [child] is centered inside the ring — typically a stat numeral.
///
/// `progress` is clamped to 0.0..1.0 so callers don't have to pre-clamp.
class StatRing extends StatelessWidget {
  const StatRing({
    super.key,
    required this.progress,
    this.diameter = 120,
    this.strokeWidth = 12,
    this.trackColor,
    this.progressColor,
    this.child,
  });

  final double progress;
  final double diameter;
  final double strokeWidth;
  final Color? trackColor;
  final Color? progressColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color track = trackColor ?? tokens.outlineMuted;
    final Color fill = progressColor ?? tokens.primary;
    final double clamped = progress.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _RingPainter(
          progress: clamped,
          trackColor: track,
          progressColor: fill,
          strokeWidth: strokeWidth,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    if (progress <= 0) return;
    final Paint progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
