import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

class MedRashSkeleton extends StatefulWidget {
  const MedRashSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<MedRashSkeleton> createState() => _MedRashSkeletonState();
}

class _MedRashSkeletonState extends State<MedRashSkeleton>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool reducedMotion = MediaQuery.of(context).disableAnimations;
    if (reducedMotion) {
      _controller.stop();
      _shimmer.stop();
    }
    return AnimatedBuilder(
      animation:
          reducedMotion ? const AlwaysStoppedAnimation<double>(0) : _controller,
      builder: (BuildContext context, Widget? _) {
        final Color base = Color.lerp(
              tokens.surfaceMuted,
              tokens.outlineMuted,
              _controller.value,
            ) ??
            tokens.surfaceMuted;
        final Widget shape = Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
        if (reducedMotion) {
          return shape;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Stack(
            children: <Widget>[
              shape,
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _shimmer,
                  builder: (BuildContext context, Widget? _) {
                    final double t = _shimmer.value;
                    // Slide a soft purple-tinted highlight diagonally across.
                    final Alignment begin = Alignment(-1.5 + 3.0 * t, -1.0);
                    final Alignment end = Alignment(-0.5 + 3.0 * t, 1.0);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: begin,
                          end: end,
                          colors: <Color>[
                            tokens.primary.withValues(alpha: 0.0),
                            tokens.primary.withValues(alpha: 0.18),
                            tokens.primary.withValues(alpha: 0.0),
                          ],
                          stops: const <double>[0.35, 0.5, 0.65],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MedRashSkeletonRow extends StatelessWidget {
  const MedRashSkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          MedRashSkeleton(width: 40, height: 40, radius: 20),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MedRashSkeleton(height: 14),
                SizedBox(height: 8),
                MedRashSkeleton(width: 120, height: 12),
              ],
            ),
          ),
          SizedBox(width: 16),
          MedRashSkeleton(width: 56, height: 16),
        ],
      ),
    );
  }
}

class MedRashSkeletonList extends StatelessWidget {
  const MedRashSkeletonList({super.key, this.rowCount = 6});

  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: rowCount,
      itemBuilder: (BuildContext context, int index) => const MedRashSkeletonRow(),
    );
  }
}

class MedRashSkeletonCard extends StatelessWidget {
  const MedRashSkeletonCard({super.key, this.height = 180});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MedRashSkeleton(height: height, radius: 16),
        const SizedBox(height: 20),
        const MedRashSkeleton(height: 18, width: 200),
        const SizedBox(height: 12),
        const MedRashSkeleton(height: 14),
        const SizedBox(height: 8),
        const MedRashSkeleton(height: 14, width: 240),
      ],
    );
  }
}
