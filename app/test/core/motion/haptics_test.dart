import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/motion/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> received = <String>[];

  setUp(() {
    received.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        received.add(call.arguments as String? ?? '');
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('selection() emits a HapticFeedbackType.selectionClick call', () async {
    await Haptics.selection();
    expect(received, <String>['HapticFeedbackType.selectionClick']);
  });

  test('submit() emits a HapticFeedbackType.mediumImpact call', () async {
    await Haptics.submit();
    expect(received, <String>['HapticFeedbackType.mediumImpact']);
  });

  test('celebrate() emits a HapticFeedbackType.heavyImpact call', () async {
    await Haptics.celebrate();
    expect(received, <String>['HapticFeedbackType.heavyImpact']);
  });
}
