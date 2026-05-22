import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/routing/app_router.dart';
import 'package:medrash_app/core/routing/auth_redirect.dart';

void main() {
  group('computeAuthRedirect', () {
    AuthRedirectDecision call({
      required bool hasProfile,
      required String matchedLocation,
      required String currentUri,
      String? nextParam,
      bool fastJoinEnabled = false,
    }) {
      return computeAuthRedirect(
        hasProfile: hasProfile,
        matchedLocation: matchedLocation,
        currentUri: currentUri,
        nextParam: nextParam,
        fastJoinEnabled: fastJoinEnabled,
        safeNext: safeNextPath,
      );
    }

    test('no profile + non-/join route bounces to /join with encoded next', () {
      final AuthRedirectDecision d = call(
        hasProfile: false,
        matchedLocation: '/session/ABCD',
        currentUri: '/session/ABCD',
      );
      expect(d.path, '/join?next=%2Fsession%2FABCD');
      expect(d.fastJoin, isFalse);
    });

    test('fast-join enabled + no profile + /session/<code> triggers mint', () {
      final AuthRedirectDecision d = call(
        hasProfile: false,
        matchedLocation: '/session/ABCD',
        currentUri: '/session/ABCD',
        fastJoinEnabled: true,
      );
      expect(d.fastJoin, isTrue);
      expect(d.path, isNull);
    });

    test('fast-join enabled but non-session route still bounces to /join', () {
      final AuthRedirectDecision d = call(
        hasProfile: false,
        matchedLocation: '/home',
        currentUri: '/home',
        fastJoinEnabled: true,
      );
      expect(d.fastJoin, isFalse);
      expect(d.path, '/join?next=%2Fhome');
    });

    test('has profile + on /join + safe next forwards to next', () {
      final AuthRedirectDecision d = call(
        hasProfile: true,
        matchedLocation: '/join',
        currentUri: '/join?next=%2Fsession%2FXYZ',
        nextParam: '/session/XYZ',
      );
      expect(d.path, '/session/XYZ');
    });

    test('has profile + on /join + unsafe next falls back to /home', () {
      final AuthRedirectDecision d = call(
        hasProfile: true,
        matchedLocation: '/join',
        currentUri: '/join?next=https%3A%2F%2Fevil.test',
        nextParam: 'https://evil.test',
      );
      expect(d.path, '/home');
    });

    test('has profile + non-join route stays', () {
      final AuthRedirectDecision d = call(
        hasProfile: true,
        matchedLocation: '/session/ABCD',
        currentUri: '/session/ABCD',
      );
      expect(d.stay, isTrue);
    });
  });
}
