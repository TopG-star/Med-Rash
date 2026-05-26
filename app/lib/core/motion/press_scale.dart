import 'package:flutter/material.dart';

import '../theme/arena_motion.dart';

/// Wraps [child] so it scales down to [pressedScale] on pointer-down and
/// springs back on release / cancel. The whole effect collapses to a no-op
/// when the platform reports `MediaQuery.disableAnimationsOf(context) == true`
/// (system-wide "reduce motion" preference).
///
/// Drop this around tap targets that already manage their own [onTap] —
/// buttons, list rows, badge tiles. It does not intercept gestures; it only
/// observes the pointer state and drives an [AnimationController].
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.duration,
    this.curve,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration? duration;
  final Curve? curve;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration ?? ArenaMotion.fast,
    lowerBound: widget.pressedScale,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _motionDisabled =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _press() {
    if (!widget.enabled || _motionDisabled) return;
    _controller.animateTo(
      widget.pressedScale,
      duration: widget.duration ?? ArenaMotion.fast,
      curve: widget.curve ?? ArenaMotion.standard,
    );
  }

  void _release() {
    if (!widget.enabled || _motionDisabled) return;
    _controller.animateTo(
      1.0,
      duration: widget.duration ?? ArenaMotion.fast,
      curve: widget.curve ?? ArenaMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget visual = AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext _, Widget? child) => Transform.scale(
        scale: _controller.value,
        child: child,
      ),
      child: widget.child,
    );

    Widget result = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: visual,
    );

    if (widget.onTap != null) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: result,
      );
    }

    return result;
  }
}
