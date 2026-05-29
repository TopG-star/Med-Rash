// Slice B7 — Flutter PII scrubber.
//
// Mirrors admin/src/lib/observability/sentry-scrubber.ts. Layered on top of
// `sendDefaultPii = false`. Strips email/IP/username from user, drops
// cookies + sensitive headers from request envelopes, scrubs query strings
// off breadcrumb URLs, redacts email-shaped substrings inside exception
// messages, and truncates long strings.
//
// sentry_flutter 9.x deprecated `copyWith` in favour of direct field
// assignment, so every mutation below writes the field in place.
import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

const int _maxStringLen = 2048;
final RegExp _emailRe =
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
const Set<String> _sensitiveHeaders = <String>{
  'cookie',
  'authorization',
  'set-cookie',
};

FutureOr<SentryEvent?> scrubEvent(SentryEvent event, Hint hint) {
  final user = event.user;
  if (user != null) {
    user.email = null;
    user.ipAddress = null;
    user.username = null;
  }

  final req = event.request;
  if (req != null) {
    if (req.url != null) {
      req.url = _stripQueryAndFragment(req.url!);
    }
    req.cookies = null;
    final hdrs = req.headers;
    if (hdrs.isNotEmpty) {
      req.headers = <String, String>{
        for (final entry in hdrs.entries)
          entry.key: _sensitiveHeaders.contains(entry.key.toLowerCase())
              ? '[redacted]'
              : entry.value,
      };
    }
  }

  final crumbs = event.breadcrumbs;
  if (crumbs != null) {
    for (final bc in crumbs) {
      final data = bc.data;
      if (data != null) {
        for (final key in data.keys.toList()) {
          final v = data[key];
          if (v is String && (key == 'url' || key == 'to' || key == 'from')) {
            data[key] = _stripQueryAndFragment(v);
          }
        }
      }
      if (bc.message != null) {
        bc.message = _redactEmails(_truncate(bc.message!));
      }
    }
  }

  final exceptions = event.exceptions;
  if (exceptions != null) {
    for (final exc in exceptions) {
      if (exc.value != null) {
        exc.value = _redactEmails(_truncate(exc.value!));
      }
    }
  }

  final message = event.message;
  if (message != null) {
    event.message = SentryMessage(
      _redactEmails(_truncate(message.formatted)),
    );
  }

  return event;
}

String _stripQueryAndFragment(String url) {
  final qIdx = url.indexOf('?');
  final hIdx = url.indexOf('#');
  final cuts = <int>[];
  if (qIdx >= 0) cuts.add(qIdx);
  if (hIdx >= 0) cuts.add(hIdx);
  if (cuts.isEmpty) return url;
  cuts.sort();
  return url.substring(0, cuts.first);
}

String _redactEmails(String value) =>
    value.replaceAll(_emailRe, '[email-redacted]');

String _truncate(String value) => value.length > _maxStringLen
    ? '${value.substring(0, _maxStringLen)}…[truncated]'
    : value;
