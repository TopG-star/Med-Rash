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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        final Color color = Color.lerp(
              tokens.surfaceMuted,
              tokens.outlineMuted,
              _controller.value,
            ) ??
            tokens.surfaceMuted;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.radius),
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
