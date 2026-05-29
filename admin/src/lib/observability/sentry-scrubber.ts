import type { Breadcrumb, ErrorEvent, TransactionEvent } from "@sentry/core";

/**
 * Slice B7 — Sentry PII scrubber.
 *
 * Layered on top of `sendDefaultPii: false`. Sentry's default scrubbing
 * handles IP + cookies + Authorization headers when sendDefaultPii is off,
 * but anything inside breadcrumbs, error messages, exception values, or
 * URL query strings can still leak. This module applies deny-rules across
 * every event surface BEFORE the network call leaves the page/server.
 *
 * Rules:
 *   1. Strip user.email + user.ip_address; keep user.id (already opaque).
 *   2. Drop URL query string + fragment on event.request.url and on every
 *      breadcrumb whose category is fetch / xhr / navigation.
 *   3. Redact known sensitive cookie names anywhere in the event tree.
 *   4. Redact email-shaped substrings inside error messages.
 *   5. Truncate strings longer than MAX_STRING_LEN to limit accidental dump.
 */

const MAX_STRING_LEN = 2_048;
const EMAIL_RE = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;
const SENSITIVE_COOKIE_NAMES = new Set<string>([
  "medrash-admin-session",
  "sb-access-token",
  "sb-refresh-token",
  "Authorization",
  "authorization",
]);

export function scrubEvent<E extends ErrorEvent | TransactionEvent>(
  event: E,
): E | null {
  if (event.user) {
    delete event.user.email;
    delete event.user.ip_address;
    delete event.user.username;
  }

  if (event.request) {
    if (typeof event.request.url === "string") {
      event.request.url = stripQueryAndFragment(event.request.url);
    }
    delete event.request.cookies;
    if (event.request.headers) {
      for (const name of Object.keys(event.request.headers)) {
        if (SENSITIVE_COOKIE_NAMES.has(name) || /cookie|authorization/i.test(name)) {
          event.request.headers[name] = "[redacted]";
        }
      }
    }
    delete event.request.data;
  }

  if (event.breadcrumbs) {
    event.breadcrumbs = event.breadcrumbs.map((bc: Breadcrumb) => {
      if (bc.data && typeof bc.data === "object") {
        if (typeof bc.data.url === "string") {
          bc.data.url = stripQueryAndFragment(bc.data.url);
        }
        if (typeof bc.data.to === "string") {
          bc.data.to = stripQueryAndFragment(bc.data.to);
        }
        if (typeof bc.data.from === "string") {
          bc.data.from = stripQueryAndFragment(bc.data.from);
        }
      }
      if (typeof bc.message === "string") {
        bc.message = redactEmails(truncate(bc.message));
      }
      return bc;
    });
  }

  if (event.exception?.values) {
    for (const exc of event.exception.values) {
      if (typeof exc.value === "string") {
        exc.value = redactEmails(truncate(exc.value));
      }
    }
  }

  if (typeof event.message === "string") {
    event.message = redactEmails(truncate(event.message));
  }

  return event;
}

function stripQueryAndFragment(url: string): string {
  const queryIdx = url.indexOf("?");
  const hashIdx = url.indexOf("#");
  const cuts = [queryIdx, hashIdx].filter((i) => i >= 0);
  if (cuts.length === 0) return url;
  return url.slice(0, Math.min(...cuts));
}

function redactEmails(value: string): string {
  return value.replace(EMAIL_RE, "[email-redacted]");
}

function truncate(value: string): string {
  return value.length > MAX_STRING_LEN
    ? `${value.slice(0, MAX_STRING_LEN)}…[truncated]`
    : value;
}
