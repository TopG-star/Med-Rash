// Slice B7 — unit tests for the Flutter PII scrubber.
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/observability/sentry_scrubber.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  final hint = Hint();

  test('removes email, username, and ip from user', () async {
    final event = SentryEvent(
      user: SentryUser(
        id: 'u_123',
        email: 'kwame@medrash.app',
        username: 'kwame',
        ipAddress: '10.0.0.5',
      ),
    );
    final out = (await scrubEvent(event, hint))!;
    expect(out.user!.id, 'u_123');
    expect(out.user!.email, isNull);
    expect(out.user!.username, isNull);
    expect(out.user!.ipAddress, isNull);
  });

  test('strips query + fragment from request URL', () async {
    final event = SentryEvent(
      request: SentryRequest(
        url: 'https://x/admin?token=secret&next=/dash#hash',
      ),
    );
    final out = (await scrubEvent(event, hint))!;
    expect(out.request!.url, 'https://x/admin');
  });

  test('redacts cookie + authorization headers', () async {
    final event = SentryEvent(
      request: SentryRequest(
        url: 'https://x',
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'medrash-admin-session=abc',
          'authorization': 'Bearer xyz',
        },
      ),
    );
    final out = (await scrubEvent(event, hint))!;
    expect(out.request!.headers['Content-Type'], 'application/json');
    expect(out.request!.headers['Cookie'], '[redacted]');
    expect(out.request!.headers['authorization'], '[redacted]');
  });

  test('redacts email-shaped substrings in exception value', () async {
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: 'StateError',
          value: 'rejected for ama.b@hospital.org while parsing',
        ),
      ],
    );
    final out = (await scrubEvent(event, hint))!;
    expect(
      out.exceptions!.first.value,
      'rejected for [email-redacted] while parsing',
    );
  });

  test('scrubs breadcrumb url + message', () async {
    final event = SentryEvent(
      breadcrumbs: [
        Breadcrumb(
          category: 'fetch',
          message: 'called for amma@med.org',
          data: {'url': 'https://api/x?token=leak'},
        ),
        Breadcrumb(
          category: 'navigation',
          data: {'from': '/a?q=x', 'to': '/b?token=y'},
        ),
      ],
    );
    final out = (await scrubEvent(event, hint))!;
    expect(out.breadcrumbs![0].data!['url'], 'https://api/x');
    expect(out.breadcrumbs![0].message, 'called for [email-redacted]');
    expect(out.breadcrumbs![1].data!['from'], '/a');
    expect(out.breadcrumbs![1].data!['to'], '/b');
  });

  test('truncates very long strings', () async {
    final long = 'a' * 3000;
    final event = SentryEvent(message: SentryMessage(long));
    final out = (await scrubEvent(event, hint))!;
    expect(out.message!.formatted.length, lessThan(long.length));
    expect(out.message!.formatted.endsWith('[truncated]'), isTrue);
  });
}
