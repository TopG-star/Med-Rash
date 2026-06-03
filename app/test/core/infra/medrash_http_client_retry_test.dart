import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/infra/medrash_http_client.dart';

void main() {
  group('MedRashHttpClient retry', () {
    test('retries on TimeoutException up to maxAttempts then rethrows',
        () async {
      int attempts = 0;
      final http.Client mock = MockClient((http.Request request) async {
        attempts += 1;
        // Force a TimeoutException by exceeding the per-attempt deadline.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      });
      final MedRashHttpClient client = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mock,
        defaultTimeout: const Duration(milliseconds: 5),
        random: math.Random(0),
      );

      await expectLater(
        () => client.postJson(
          'profile-sync',
          <String, Object?>{'x': 1},
          retryPolicy: const RetryPolicy(
            maxAttempts: 3,
            initialBackoff: Duration(milliseconds: 1),
            maxBackoff: Duration(milliseconds: 2),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(attempts, 3);
    });

    test('retries on 5xx and succeeds when a later attempt returns 2xx',
        () async {
      int attempts = 0;
      final http.Client mock = MockClient((http.Request request) async {
        attempts += 1;
        if (attempts < 2) {
          return http.Response('{"code":"BOOM"}', 503,
              headers: <String, String>{'content-type': 'application/json'});
        }
        return http.Response(jsonEncode(<String, Object?>{'ok': true}), 200,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final MedRashHttpClient client = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mock,
        random: math.Random(0),
      );

      final Map<String, dynamic> body = await client.postJson(
        'attempt-submit',
        <String, Object?>{'x': 1},
        retryPolicy: const RetryPolicy(
          maxAttempts: 3,
          initialBackoff: Duration(milliseconds: 1),
          maxBackoff: Duration(milliseconds: 2),
        ),
      );
      expect(body['ok'], true);
      expect(attempts, 2);
    });

    test('does NOT retry on 4xx', () async {
      int attempts = 0;
      final http.Client mock = MockClient((http.Request request) async {
        attempts += 1;
        return http.Response('{"code":"VALIDATION_ERROR"}', 400,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final MedRashHttpClient client = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mock,
        random: math.Random(0),
      );

      await expectLater(
        () => client.postJson(
          'profile-sync',
          <String, Object?>{},
          retryPolicy: const RetryPolicy(
            maxAttempts: 3,
            initialBackoff: Duration(milliseconds: 1),
            maxBackoff: Duration(milliseconds: 2),
          ),
        ),
        throwsA(isA<MedRashGateException>()),
      );
      expect(attempts, 1);
    });

    test('forwards Idempotency-Key header when provided', () async {
      String? observedKey;
      final http.Client mock = MockClient((http.Request request) async {
        observedKey = request.headers['idempotency-key'];
        return http.Response('{}', 200,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final MedRashHttpClient client = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mock,
      );

      await client.postJson(
        'session-create',
        <String, Object?>{},
        idempotencyKey: 'abc-123',
      );
      expect(observedKey, 'abc-123');
    });

    test('default RetryPolicy.none keeps single-shot behaviour for callers '
        'that do not opt in', () async {
      int attempts = 0;
      final http.Client mock = MockClient((http.Request request) async {
        attempts += 1;
        return http.Response('{"code":"BOOM"}', 503,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final MedRashHttpClient client = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mock,
      );

      await expectLater(
        () => client.postJson('quiz-list', <String, Object?>{}),
        throwsA(isA<MedRashGateException>()),
      );
      expect(attempts, 1);
    });
  });
}
