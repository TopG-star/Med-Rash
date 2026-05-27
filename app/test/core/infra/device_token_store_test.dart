import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/device_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceTokenStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Future<DeviceTokenStore> buildStore({
      required http.Client httpClient,
      DateTime Function()? clock,
    }) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return DeviceTokenStore(
        preferences: prefs,
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        gateApiKey: 'gate-key-for-test',
        deviceIdentityService: DeviceIdentityService(prefs),
        httpClient: httpClient,
        clock: clock,
      );
    }

    test('mints a token on first call and caches it for subsequent calls',
        () async {
      int mintCount = 0;
      final http.Client mockHttp = MockClient((http.Request request) async {
        expect(request.url.path, endsWith('device-token'));
        expect(request.headers['x-medrash-gate-key'], 'gate-key-for-test');
        final Map<String, dynamic> body =
            jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['deviceInstallId'], isNotNull);
        expect(body['participantId'], isNotNull);
        mintCount += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'token': 'header.payload-$mintCount.sig',
            'issuedAt': 1700000000,
            'expiresAt': 1700086400, // +24h
            'refreshAfter': 1700082800, // -1h before exp
          }),
          200,
        );
      });

      final DeviceTokenStore store = await buildStore(
        httpClient: mockHttp,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000500 * 1000),
      );

      final String? first = await store.currentToken();
      final String? second = await store.currentToken();

      expect(first, 'header.payload-1.sig');
      expect(second, 'header.payload-1.sig');
      expect(mintCount, 1);
    });

    test('refreshes the cached token once now >= refreshAfter', () async {
      int mintCount = 0;
      final http.Client mockHttp = MockClient((http.Request request) async {
        mintCount += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'token': 'tok-$mintCount',
            'issuedAt': 1700000000,
            'expiresAt': 1700086400,
            'refreshAfter': 1700082800,
          }),
          200,
        );
      });

      // First call at t=1700000500 — mints tok-1.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final DeviceTokenStore early = DeviceTokenStore(
        preferences: prefs,
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        gateApiKey: 'gate-key',
        deviceIdentityService: DeviceIdentityService(prefs),
        httpClient: mockHttp,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000500 * 1000),
      );
      expect(await early.currentToken(), 'tok-1');

      // Second store (simulating app restart) past the refreshAfter — re-mints.
      final DeviceTokenStore late = DeviceTokenStore(
        preferences: prefs,
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        gateApiKey: 'gate-key',
        deviceIdentityService: DeviceIdentityService(prefs),
        httpClient: mockHttp,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700083500 * 1000),
      );
      expect(await late.currentToken(), 'tok-2');
      expect(mintCount, 2);
    });

    test('returns null when mint fails and there is no usable cache',
        () async {
      final http.Client mockHttp = MockClient(
        (http.Request request) async => http.Response('{"ok":false}', 500),
      );
      final DeviceTokenStore store = await buildStore(httpClient: mockHttp);
      expect(await store.currentToken(), isNull);
    });

    test('returns the cached token when mint fails but cache is still valid',
        () async {
      // Pre-seed a valid cached token.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'medrash.device_token.value': 'cached-token',
        'medrash.device_token.expires_at': 1700086400,
        'medrash.device_token.refresh_after': 1700082800,
      });
      final http.Client mockHttp = MockClient(
        (http.Request request) async => http.Response('boom', 500),
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final DeviceTokenStore store = DeviceTokenStore(
        preferences: prefs,
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        gateApiKey: 'gate-key',
        deviceIdentityService: DeviceIdentityService(prefs),
        httpClient: mockHttp,
        // After refreshAfter, before expiresAt.
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700083500 * 1000),
      );
      expect(await store.currentToken(), 'cached-token');
    });

    test('clear() wipes the cached token', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'medrash.device_token.value': 'cached-token',
        'medrash.device_token.expires_at': 1700086400,
        'medrash.device_token.refresh_after': 1700082800,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final DeviceTokenStore store = DeviceTokenStore(
        preferences: prefs,
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        gateApiKey: 'gate-key',
        deviceIdentityService: DeviceIdentityService(prefs),
        httpClient: MockClient(
          (http.Request request) async => http.Response('{}', 500),
        ),
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700083500 * 1000),
      );
      await store.clear();
      expect(prefs.getString('medrash.device_token.value'), isNull);
      expect(prefs.getInt('medrash.device_token.expires_at'), isNull);
      expect(prefs.getInt('medrash.device_token.refresh_after'), isNull);
    });

    test('concurrent currentToken() calls dedupe into a single mint', () async {
      int mintCount = 0;
      final http.Client mockHttp = MockClient((http.Request request) async {
        mintCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(
          jsonEncode(<String, Object?>{
            'token': 'singleton-token',
            'expiresAt': 1700086400,
            'refreshAfter': 1700082800,
          }),
          200,
        );
      });
      final DeviceTokenStore store = await buildStore(
        httpClient: mockHttp,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000500 * 1000),
      );
      final List<String?> results = await Future.wait(<Future<String?>>[
        store.currentToken(),
        store.currentToken(),
        store.currentToken(),
      ]);
      expect(results, everyElement('singleton-token'));
      expect(mintCount, 1);
    });
  });
}
