import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/features/profile/models/user_profile.dart';
import 'package:medrash_app/features/profile/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LocalProfileRepository.mintGuestProfile', () {
    test('persists a Guest-XXXX nickname round-trippable via getProfile', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LocalProfileRepository repo = LocalProfileRepository(prefs);

      final UserProfile minted = await repo.mintGuestProfile(seedSuffix: 4242);
      expect(minted.nickname, 'Guest-4242');
      expect(minted.fullName, 'Guest-4242');
      expect(minted.specialty, 'Doctor');
      expect(minted.facility, '');

      final UserProfile? loaded = await repo.getProfile();
      expect(loaded, isNotNull);
      expect(loaded!.nickname, 'Guest-4242');
    });

    test('omitting seedSuffix yields a nickname matching isGuestNickname', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LocalProfileRepository repo = LocalProfileRepository(prefs);

      final UserProfile minted = await repo.mintGuestProfile();
      expect(ProfileRepository.isGuestNickname(minted.nickname), isTrue);
    });
  });

  group('ProfileRepository.isGuestNickname', () {
    test('matches the canonical guest pattern', () {
      expect(ProfileRepository.isGuestNickname('Guest-1234'), isTrue);
      expect(ProfileRepository.isGuestNickname('Guest-999'), isTrue);
      expect(ProfileRepository.isGuestNickname('  Guest-1234  '), isTrue);
    });

    test('rejects custom nicknames and near-misses', () {
      expect(ProfileRepository.isGuestNickname('Alice'), isFalse);
      expect(ProfileRepository.isGuestNickname('Guest'), isFalse);
      expect(ProfileRepository.isGuestNickname('Guest-12'), isFalse);
      expect(ProfileRepository.isGuestNickname('Guest-12345'), isFalse);
      expect(ProfileRepository.isGuestNickname('guest-1234'), isFalse);
      expect(ProfileRepository.isGuestNickname('SwiftDoctor123'), isFalse);
    });
  });
}
