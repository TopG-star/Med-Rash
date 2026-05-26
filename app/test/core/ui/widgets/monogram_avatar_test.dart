import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/ui/widgets/monogram_avatar.dart';

void main() {
  group('MonogramAvatar.initialsFor', () {
    test('returns "?" for empty or whitespace input', () {
      expect(MonogramAvatar.initialsFor(''), '?');
      expect(MonogramAvatar.initialsFor('   '), '?');
    });

    test('takes first letter of first and last word', () {
      expect(MonogramAvatar.initialsFor('John Kofi'), 'JK');
      expect(MonogramAvatar.initialsFor('Ama Serwaa Mensah'), 'AM');
      expect(MonogramAvatar.initialsFor('  Kwame   Asante  '), 'KA');
    });

    test('uses camelcase capitals for single-token nicknames', () {
      expect(MonogramAvatar.initialsFor('SwiftDoctor777'), 'SD');
      expect(MonogramAvatar.initialsFor('BrightSurgeon42'), 'BS');
    });

    test('falls back to first two chars upper-cased', () {
      expect(MonogramAvatar.initialsFor('ama'), 'AM');
      expect(MonogramAvatar.initialsFor('k'), 'K');
    });
  });
}
