import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/ui/responsive.dart';

void main() {
  group('medRashBreakpointForWidth', () {
    test('returns compact below 600 dp', () {
      expect(medRashBreakpointForWidth(0), MedRashBreakpoint.compact);
      expect(medRashBreakpointForWidth(599.999), MedRashBreakpoint.compact);
    });

    test('returns medium at 600 dp through 1023.999 dp', () {
      expect(medRashBreakpointForWidth(600), MedRashBreakpoint.medium);
      expect(medRashBreakpointForWidth(1023.999), MedRashBreakpoint.medium);
    });

    test('returns expanded at 1024 dp and above', () {
      expect(medRashBreakpointForWidth(1024), MedRashBreakpoint.expanded);
      expect(medRashBreakpointForWidth(4096), MedRashBreakpoint.expanded);
    });
  });

  group('ResponsiveValue.resolve', () {
    test('compact-only value applies to every breakpoint', () {
      const ResponsiveValue<int> rv = ResponsiveValue<int>(compact: 8);
      expect(rv.resolve(MedRashBreakpoint.compact), 8);
      expect(rv.resolve(MedRashBreakpoint.medium), 8);
      expect(rv.resolve(MedRashBreakpoint.expanded), 8);
    });

    test('medium overrides compact; expanded falls back to medium', () {
      const ResponsiveValue<int> rv =
          ResponsiveValue<int>(compact: 8, medium: 16);
      expect(rv.resolve(MedRashBreakpoint.compact), 8);
      expect(rv.resolve(MedRashBreakpoint.medium), 16);
      expect(rv.resolve(MedRashBreakpoint.expanded), 16);
    });

    test('explicit expanded value wins over medium fallback', () {
      const ResponsiveValue<int> rv =
          ResponsiveValue<int>(compact: 8, medium: 16, expanded: 24);
      expect(rv.resolve(MedRashBreakpoint.compact), 8);
      expect(rv.resolve(MedRashBreakpoint.medium), 16);
      expect(rv.resolve(MedRashBreakpoint.expanded), 24);
    });
  });

  group('ResponsiveBuilder', () {
    Future<MedRashBreakpoint> pumpAndRead(
      WidgetTester tester,
      Size size,
    ) async {
      late MedRashBreakpoint observed;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ResponsiveBuilder(
              builder: (BuildContext context, MedRashBreakpoint bp) {
                observed = bp;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      return observed;
    }

    testWidgets('yields compact below 600 dp', (WidgetTester tester) async {
      final MedRashBreakpoint bp = await pumpAndRead(tester, const Size(400, 800));
      expect(bp, MedRashBreakpoint.compact);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });

    testWidgets('yields medium between 600 and 1024 dp',
        (WidgetTester tester) async {
      final MedRashBreakpoint bp = await pumpAndRead(tester, const Size(800, 1000));
      expect(bp, MedRashBreakpoint.medium);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });

    testWidgets('yields expanded at 1024 dp and above',
        (WidgetTester tester) async {
      final MedRashBreakpoint bp = await pumpAndRead(tester, const Size(1280, 800));
      expect(bp, MedRashBreakpoint.expanded);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}
