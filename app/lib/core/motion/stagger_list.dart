import 'package:flutter/material.dart';

import '../theme/arena_motion.dart';

/// Renders [children] in a vertical column with a per-row entrance stagger
/// (fade + small upward slide). One parent controller drives every row via
/// `Interval` curves — deterministic in tests, no per-item timers.
///
/// Honours reduced-motion: when on, every child is shown at its final state
/// immediately with no offset/opacity tween.
class StaggerList extends StatefulWidget {
  const StaggerList({
    super.key,
    required this.children,
    this.itemDuration,
    this.itemDelay = const Duration(milliseconds: 40),
    this.startDelay = Duration.zero,
    this.slideDistance = 12,
    this.curve,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.min,
  });

  final List<Widget> children;
  final Duration? itemDuration;
  final Duration itemDelay;
  final Duration startDelay;
  final double slideDistance;
  final Curve? curve;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  State<StaggerList> createState() => _StaggerListState();
}

class _StaggerListState extends State<StaggerList>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Duration _itemDuration;
  late int _totalMicros;

  @override
  void initState() {
    super.initState();
    _rebuildTimeline();
    if (_totalMicros > 0) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant StaggerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length ||
        oldWidget.itemDuration != widget.itemDuration ||
        oldWidget.itemDelay != widget.itemDelay ||
        oldWidget.startDelay != widget.startDelay) {
      _controller.dispose();
      _rebuildTimeline();
      if (_totalMicros > 0) _controller.forward();
    }
  }

  void _rebuildTimeline() {
    _itemDuration = widget.itemDuration ?? ArenaMotion.medium;
    final int n = widget.children.length;
    _totalMicros = n == 0
        ? 0
        : widget.startDelay.inMicroseconds +
            widget.itemDelay.inMicroseconds * (n - 1) +
            _itemDuration.inMicroseconds;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(microseconds: _totalMicros == 0 ? 1 : _totalMicros),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Curve baseCurve = widget.curve ?? ArenaMotion.standard;

    if (reduced || _totalMicros == 0) {
      return Column(
        crossAxisAlignment: widget.crossAxisAlignment,
        mainAxisSize: widget.mainAxisSize,
        children: <Widget>[
          for (final Widget c in widget.children)
            Opacity(opacity: 1.0, child: c),
        ],
      );
    }

    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      mainAxisSize: widget.mainAxisSize,
      children: <Widget>[
        for (int i = 0; i < widget.children.length; i++)
          _StaggerItem(
            controller: _controller,
            beginFraction: (widget.startDelay.inMicroseconds +
                    widget.itemDelay.inMicroseconds * i) /
                _totalMicros,
            endFraction: (widget.startDelay.inMicroseconds +
                    widget.itemDelay.inMicroseconds * i +
                    _itemDuration.inMicroseconds) /
                _totalMicros,
            curve: baseCurve,
            slideDistance: widget.slideDistance,
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _StaggerItem extends StatelessWidget {
  const _StaggerItem({
    required this.controller,
    required this.beginFraction,
    required this.endFraction,
    required this.curve,
    required this.slideDistance,
    required this.child,
  });

  final AnimationController controller;
  final double beginFraction;
  final double endFraction;
  final Curve curve;
  final double slideDistance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> t = CurvedAnimation(
      parent: controller,
      curve: Interval(
        beginFraction.clamp(0.0, 1.0),
        endFraction.clamp(0.0, 1.0),
        curve: curve,
      ),
    );
    return AnimatedBuilder(
      animation: t,
      builder: (BuildContext _, Widget? c) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - t.value) * slideDistance),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
