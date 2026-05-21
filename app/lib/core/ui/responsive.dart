import 'package:flutter/widgets.dart';

/// Layout breakpoints used across MedRash participant screens.
///
/// We bias toward three buckets — anything more granular has to fight Flutter's
/// `MediaQuery` shape on the web, where the same physical phone reports
/// different widths depending on whether it's locked landscape or PWA-installed.
enum MedRashBreakpoint {
  /// `< 600 dp`. Single-column phones, narrow web pop-ups.
  compact,

  /// `600 dp \u2013 1024 dp`. Tablets, foldables, half-screen browser windows.
  medium,

  /// `> 1024 dp`. Desktop browsers, projector mirrors.
  expanded,
}

/// Convenience accessors for breakpoints + a single content width that keeps
/// reading-flow tight on big monitors. Picked 560 dp as a Material-spec-ish
/// reading column width \u2014 wider than mobile, narrower than a TV.
extension MedRashBreakpointContext on BuildContext {
  MedRashBreakpoint get breakpoint {
    final double width = MediaQuery.sizeOf(this).width;
    if (width < 600) {
      return MedRashBreakpoint.compact;
    }
    if (width < 1024) {
      return MedRashBreakpoint.medium;
    }
    return MedRashBreakpoint.expanded;
  }

  bool get isCompact => breakpoint == MedRashBreakpoint.compact;
  bool get isExpanded => breakpoint == MedRashBreakpoint.expanded;
}

/// Centers and caps the readable width of its child once the screen is wider
/// than ~560 dp. On phones it does nothing \u2014 the child already fills.
/// Wrap the top-level `ListView`/`Column` of a participant screen with this so
/// content stops stretching across desktop / projector views.
class MedRashConstrainedBody extends StatelessWidget {
  const MedRashConstrainedBody({
    super.key,
    required this.child,
    this.maxWidth = 560,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
