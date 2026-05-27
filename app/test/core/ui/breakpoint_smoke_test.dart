import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/responsive.dart';
import 'package:medrash_app/core/ui/widgets/empty_state.dart';
import 'package:medrash_app/core/ui/widgets/quiz_progress_bar.dart';

/// Pilot breakpoints called out in `docs/ui-overhaul-plan.md` Slice 6d:
/// phone (390), tablet (820), laptop (1280), widescreen (1920).
const List<double> _pilotWidths = <double>[390, 820, 1280, 1920];

const Map<int, MedRashBreakpoint> _expectedBucket = <int, MedRashBreakpoint>{
  390: MedRashBreakpoint.compact,
  820: MedRashBreakpoint.medium,
  1280: MedRashBreakpoint.expanded,
  1920: MedRashBreakpoint.expanded,
};

Widget _wrap(Widget child, double width) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 900)),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('Breakpoint smoke - pilot widths 390/820/1280/1920', () {
    for (final double w in _pilotWidths) {
      test('width=$w resolves to ${_expectedBucket[w.toInt()]}', () {
        expect(medRashBreakpointForWidth(w), _expectedBucket[w.toInt()]);
      });
    }

    for (final double w in _pilotWidths) {
      testWidgets('MedRashConstrainedBody caps to 560dp at width=$w',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(w, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            MedRashConstrainedBody(
              child: Container(
                key: const Key('child'),
                height: 100,
                color: const Color(0xFF000000),
              ),
            ),
            w,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final double childWidth =
            tester.getSize(find.byKey(const Key('child'))).width;
        // <560 phones get full bleed; wider screens cap at 560.
        final double expected = w < 560 ? w : 560;
        expect(childWidth, expected);
      });
    }

    for (final double w in _pilotWidths) {
      testWidgets('MedRashEmptyState renders without overflow at width=$w',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(w, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            const MedRashConstrainedBody(
              child: MedRashEmptyState(
                icon: Icons.emoji_events_rounded,
                title: 'Be the first on the podium',
                body:
                    'No ranked attempts have synced yet. Finish a ranked attempt to claim the inaugural top spot.',
              ),
            ),
            w,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    for (final double w in _pilotWidths) {
      testWidgets('QuizProgressBar renders without overflow at width=$w',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(w, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            const Padding(
              padding: EdgeInsets.all(16),
              child: QuizProgressBar(progress: 0.5),
            ),
            w,
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
