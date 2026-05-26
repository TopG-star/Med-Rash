import 'package:flutter/widgets.dart';

import '../theme/arena_motion.dart';

/// Animates an integer from [from] to [value] using [TweenAnimationBuilder].
/// Designed for score / XP / rank-points reveals where the destination number
/// is known up-front and the journey itself is the celebration.
///
/// Collapses to the final value with no animation when reduced-motion is on.
class CountUpNumber extends StatelessWidget {
  const CountUpNumber({
    super.key,
    required this.value,
    this.from = 0,
    this.duration,
    this.curve,
    this.style,
    this.textAlign,
    this.semanticLabel,
    this.formatter,
  });

  final int value;
  final int from;
  final Duration? duration;
  final Curve? curve;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? semanticLabel;

  /// Optional formatter (e.g. thousands separator). Defaults to `toString()`.
  final String Function(int current)? formatter;

  @override
  Widget build(BuildContext context) {
    final bool reduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final int begin = reduced ? value : from;
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: begin, end: value),
      duration: reduced ? Duration.zero : (duration ?? ArenaMotion.slow),
      curve: curve ?? ArenaMotion.standard,
      builder: (BuildContext _, int current, Widget? __) {
        final String text =
            formatter != null ? formatter!(current) : current.toString();
        return Text(
          text,
          style: style,
          textAlign: textAlign,
          semanticsLabel: semanticLabel,
        );
      },
    );
  }
}
