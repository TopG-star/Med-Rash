import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity_service.dart';
import 'turnstile_token_provider.dart';

/// Slice A2 phase 2 / 3b — client-side custodian of the per-device bearer
/// token minted by `admin/netlify/functions/device-token.ts`.
///
/// Responsibilities:
///   * Mint a token via POST `/device-token` (bootstrap is gated by the
///     legacy gate key — that's the whole point of the transitional window).
///   * Persist `{token, issuedAt, expiresAt, refreshAfter}` to SharedPreferences.
///   * Hand the cached token to [MedRashHttpClient.tokenProvider] for every
///     subsequent participant call.
///   * Proactively re-mint once `now >= refreshAfter` (default: 1h before
///     expiry, server-driven).
///   * Single-flight concurrent mints so a burst of requests at startup does
///     not stampede the endpoint.
///
/// Failure mode: if mint fails and there is no cached token (or the cached
/// one is expired), [currentToken] returns null and [MedRashHttpClient] simply
/// omits the Authorization header. That leaves the server falling back to the
/// legacy `x-medrash-gate-key` path — exactly the Phase 1 dual-path guarantee.
class DeviceTokenStore {
  DeviceTokenStore({
    required SharedPreferences preferences,
    required String functionsBaseUrl,
    required String? gateApiKey,
    required DeviceIdentityService deviceIdentityService,
    TurnstileTokenProvider? turnstileTokenProvider,
    http.Client? httpClient,
    DateTime Function()? clock,
  })  : _preferences = preferences,
        _baseFunctionsUri = _normalizeFunctionsUri(functionsBaseUrl),
        _gateApiKey = gateApiKey,
        _deviceIdentityService = deviceIdentityService,
        _turnstileTokenProvider = turnstileTokenProvider,
        _httpClient = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  static const String _tokenKey = 'medrash.device_token.value';
  static const String _expiresAtKey = 'medrash.device_token.expires_at';
  static const String _refreshAfterKey = 'medrash.device_token.refresh_after';

  final SharedPreferences _preferences;
  final Uri _baseFunctionsUri;
  final String? _gateApiKey;
  final DeviceIdentityService _deviceIdentityService;
  final TurnstileTokenProvider? _turnstileTokenProvider;
  final http.Client _httpClient;
  final DateTime Function() _clock;

  Future<String?>? _inflight;

  static Uri _normalizeFunctionsUri(String raw) {
    final String normalized = raw.endsWith('/') ? raw : '$raw/';
    return Uri.parse(normalized);
  }

  /// Returns a valid bearer token, minting or refreshing as needed.
  /// Returns null if no token can be obtained (network failure with no cache
  /// usable). Caller treats null as "skip the Authorization header".
  Future<String?> currentToken() {
    final Future<String?>? existing = _inflight;
    if (existing != null) {
      return existing;
    }

    final Future<String?> work = _resolve();
    _inflight = work;
    work.whenComplete(() {
      if (identical(_inflight, work)) {
        _inflight = null;
      }
    });
    return work;
  }

  Future<String?> _resolve() async {
    final int nowSec = _clock().millisecondsSinceEpoch ~/ 1000;
    final String? cached = _preferences.getString(_tokenKey);
    final int cachedExp = _preferences.getInt(_expiresAtKey) ?? 0;
    final int cachedRefresh = _preferences.getInt(_refreshAfterKey) ?? 0;

    if (cached != null && cached.isNotEmpty && nowSec < cachedRefresh) {
      return cached;
    }

    try {
      return await _mint();
    } catch (error, stack) {
      developer.log(
        'device-token mint failed',
        name: 'DeviceTokenStore',
        error: error,
        stackTrace: stack,
      );
      if (cached != null && cached.isNotEmpty && nowSec < cachedExp) {
        // Cached token is past its refresh window but still valid — keep
        // using it rather than dropping to no-auth.
        return cached;
      }
      return null;
    }
  }

  Future<String> _mint() async {
    final String deviceInstallId =
        await _deviceIdentityService.getOrCreateDeviceId();
    final String participantId =
        await _deviceIdentityService.getOrCreateParticipantId();

    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
    };
    final String gateKey = _gateApiKey?.trim() ?? '';
    if (gateKey.isNotEmpty) {
      headers['x-medrash-gate-key'] = gateKey;
    }

    // Phase 3b — fetch a Turnstile token when a provider is configured.
    // Provider returns null on web-without-site-key, non-web platforms,
    // widget timeout, or Cloudflare error; in all those cases we drop
    // through to the gate-key bootstrap (Phase 3b transition only).
    String? turnstileToken;
    try {
      turnstileToken = await _turnstileTokenProvider?.fetchToken();
    } catch (error, stack) {
      developer.log(
        'TurnstileTokenProvider threw; continuing with gate-key bootstrap',
        name: 'DeviceTokenStore',
        error: error,
        stackTrace: stack,
      );
      turnstileToken = null;
    }

    final Map<String, Object?> body = <String, Object?>{
      'deviceInstallId': deviceInstallId,
      'participantId': participantId,
    };
    if (turnstileToken != null && turnstileToken.isNotEmpty) {
      body['turnstileToken'] = turnstileToken;
    }

    final http.Response response = await _httpClient.post(
      _baseFunctionsUri.resolve('device-token'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'device-token endpoint returned ${response.statusCode}: ${response.body}',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('device-token response was not a JSON object.');
    }
    final String token = (decoded['token'] as Object?)?.toString() ?? '';
    final int expiresAt =
        _readSecondsField(decoded['expiresAt']) ?? 0;
    final int refreshAfter =
        _readSecondsField(decoded['refreshAfter']) ?? expiresAt;

    if (token.isEmpty || expiresAt <= 0) {
      throw StateError('device-token response missing token/expiresAt fields.');
    }

    await _preferences.setString(_tokenKey, token);
    await _preferences.setInt(_expiresAtKey, expiresAt);
    await _preferences.setInt(_refreshAfterKey, refreshAfter);

    return token;
  }

  int? _readSecondsField(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  /// Wipe the cached token. Call after a hard sign-out / device-rotation so
  /// the next request mints a fresh one bound to the new identity.
  Future<void> clear() async {
    await _preferences.remove(_tokenKey);
    await _preferences.remove(_expiresAtKey);
    await _preferences.remove(_refreshAfterKey);
  }
}
