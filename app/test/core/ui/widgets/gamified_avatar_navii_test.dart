import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/gamified_avatar.dart';
import 'package:medrash_app/core/ui/widgets/monogram_avatar.dart';
import 'package:medrash_app/core/ui/widgets/navii_svg_loader.dart';
import 'package:medrash_app/features/profile/models/avatar_spec.dart';

class _StubLoader implements NaviiSvgLoader {
  _StubLoader(this._result);

  final Future<Uint8List?> Function(String seed, int pixelSize) _result;
  final List<String> recordedSeeds = <String>[];

  @override
  Future<Uint8List?> load({required String seed, required int pixelSize}) {
    recordedSeeds.add(seed);
    return _result(seed, pixelSize);
  }
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  // NOTE: `AppConfig.enableNaviiAvatars` is a const compiled from
  // `--dart-define`. In the unit test binary it is false, so every
  // `NaviiAvatarSpec` short-circuits to its monogram fallback regardless
  // of which loader is registered. These tests pin that contract.

  tearDown(() {
    globalNaviiSvgLoader = null;
  });

  testWidgets('falls back to monogram when seed is empty', (tester) async {
    final loader = _StubLoader((_, __) async => Uint8List.fromList(<int>[1]));
    globalNaviiSvgLoader = loader;

    await tester.pumpWidget(_host(const GamifiedAvatar(
      spec: NaviiAvatarSpec(seed: '   ', fallbackSource: 'Sara Mensah'),
      diameter: 64,
    )));

    expect(find.byType(MonogramAvatar), findsOneWidget);
    expect(find.text('SM'), findsOneWidget);
    expect(loader.recordedSeeds, isEmpty);
  });

  testWidgets('falls back to monogram when loader is not registered',
      (tester) async {
    globalNaviiSvgLoader = null;

    await tester.pumpWidget(_host(const GamifiedAvatar(
      spec: NaviiAvatarSpec(
        seed: '11111111-2222-3333-4444-555555555555',
        fallbackSource: 'Kojo Anan',
      ),
      diameter: 64,
    )));

    expect(find.byType(MonogramAvatar), findsOneWidget);
    expect(find.text('KA'), findsOneWidget);
  });

  testWidgets('falls back to monogram when loader returns null',
      (tester) async {
    final loader = _StubLoader((_, __) async => null);
    globalNaviiSvgLoader = loader;

    await tester.pumpWidget(_host(const GamifiedAvatar(
      spec: NaviiAvatarSpec(
        seed: '11111111-2222-3333-4444-555555555555',
        fallbackSource: 'Yaa Asantewaa',
      ),
      diameter: 64,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(MonogramAvatar), findsOneWidget);
    expect(find.text('YA'), findsOneWidget);
  });
}
