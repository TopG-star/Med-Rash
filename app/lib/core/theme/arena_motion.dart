import 'package:flutter/animation.dart';

/// Centralised motion vocabulary for the Vibrant Pulse system. Screens and
/// widgets should pull durations and curves from here so feedback feels
/// consistent across the app (hover, press, route transitions, score
/// counters, modal entrances, etc.).
class ArenaMotion {
  const ArenaMotion._();

  /// Fast interactive feedback (button press, ripple, focus).
  static const Duration fast = Duration(milliseconds: 150);

  /// Medium-paced UI transitions (card hover lift, badge reveal, tab swap).
  static const Duration medium = Duration(milliseconds: 280);

  /// Slow celebratory or layout transitions (podium reveal, page hero).
  static const Duration slow = Duration(milliseconds: 480);

  /// Standard easing for most UI motion.
  static const Curve standard = Curves.easeOutCubic;

  /// Emphasised easing for celebratory or attention-grabbing motion.
  static const Curve emphasis = Curves.easeOutBack;

  /// Linear timing for progress bars and counters.
  static const Curve linear = Curves.linear;
}
