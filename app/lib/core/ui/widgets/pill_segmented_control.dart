import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// One segment in a `PillSegmentedControl`. Generic on `T` so callers can
/// bind it to whatever value type their state uses (enum, String, int).
@immutable
class PillSegment<T> {
  const PillSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Horizontal pill of mutually-exclusive segments (UI 1 reference: the
/// Top / Quiz / Categories / Friends switcher on Discover). The currently
/// selected segment fills with the primary color; others stay transparent
/// over the muted surface track.
class PillSegmentedControl<T> extends StatelessWidget {
  const PillSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 44,
  });

  final List<PillSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    assert(segments.isNotEmpty, 'segments must not be empty');
    final tokens = context.arenaTokens;
    final TextStyle baseStyle =
        Theme.of(context).textTheme.labelLarge ?? const TextStyle();

    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: tokens.outlineMuted, width: 1),
      ),
      child: Row(
        children: <Widget>[
          for (final PillSegment<T> seg in segments)
            Expanded(
              child: _SegmentButton<T>(
                segment: seg,
                isSelected: seg.value == value,
                onTap: () => onChanged(seg.value),
                textStyle: baseStyle,
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    required this.segment,
    required this.isSelected,
    required this.onTap,
    required this.textStyle,
  });

  final PillSegment<T> segment;
  final bool isSelected;
  final VoidCallback onTap;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? tokens.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            segment.label,
            style: textStyle.copyWith(
              color: isSelected ? Colors.white : tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
