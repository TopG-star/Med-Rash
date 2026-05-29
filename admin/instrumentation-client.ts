/**
 * Slice B7 — Client-side telemetry (browser runtime).
 *
 * Auto-loaded by Next.js 16 on the client. When NEXT_PUBLIC_SENTRY_DSN is
 * not set, Sentry.init() is a no-op — safe to ship before the DSN is
 * provisioned, identical posture to MEDRASH_ADMIN_SESSION_SECRET in B1.
 *
 * PII discipline: this runtime sees the admin's browser, so we must scrub
 * email + IP + session tokens BEFORE the event leaves the page.
 */
import * as Sentry from "@sentry/nextjs";

import { scrubEvent } from "@/lib/observability/sentry-scrubber";

const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    release: process.env.NEXT_PUBLIC_SENTRY_RELEASE,
    environment: process.env.NEXT_PUBLIC_SENTRY_ENVIRONMENT ?? "development",

    // Sampling — start conservative; tune in the Sentry org as data lands.
    tracesSampleRate: 0.1,

    // Session Replay is DISABLED — replay captures full DOM including any
    // PII rendered on screen (email, attempt scores, participant names).
    // Re-enable only with a privacy review + selector-based masking config.
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,

    // No default PII attached by the SDK (IP, cookies, headers).
    sendDefaultPii: false,

    // Defence-in-depth scrubber runs on every event AND every breadcrumb
    // regardless of integration source. See sentry-scrubber.ts for rules.
    beforeSend(event) {
      return scrubEvent(event);
    },
    beforeBreadcrumb(breadcrumb) {
      if (
        breadcrumb.category === "fetch" ||
        breadcrumb.category === "xhr" ||
        breadcrumb.category === "navigation"
      ) {
        if (breadcrumb.data?.url) {
          breadcrumb.data.url = stripQueryAndFragment(
            String(breadcrumb.data.url),
          );
        }
      }
      return breadcrumb;
    },

    ignoreErrors: [
      // Browser noise that the admin user cannot act on.
      "ResizeObserver loop limit exceeded",
      "ResizeObserver loop completed with undelivered notifications",
      "Non-Error promise rejection captured",
    ],
  });
}

function stripQueryAndFragment(url: string): string {
  const queryIdx = url.indexOf("?");
  const hashIdx = url.indexOf("#");
  const cutAt = [queryIdx, hashIdx].filter((i) => i >= 0).sort((a, b) => a - b)[0];
  return cutAt === undefined ? url : url.slice(0, cutAt);
}

// Required by Next.js so router transitions are captured.
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
