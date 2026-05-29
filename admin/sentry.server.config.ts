/**
 * Slice B7 — Server runtime Sentry init.
 *
 * Loaded by instrumentation.ts when NEXT_RUNTIME === "nodejs". Covers
 * server actions, API routes, server components, and the build worker.
 */
import * as Sentry from "@sentry/nextjs";

import { scrubEvent } from "@/lib/observability/sentry-scrubber";

const dsn = process.env.SENTRY_DSN ?? process.env.NEXT_PUBLIC_SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    release: process.env.SENTRY_RELEASE ?? process.env.NEXT_PUBLIC_SENTRY_RELEASE,
    environment:
      process.env.SENTRY_ENVIRONMENT ??
      process.env.NEXT_PUBLIC_SENTRY_ENVIRONMENT ??
      "development",

    tracesSampleRate: 0.1,

    // Never attach raw request bodies, cookies, headers, or IPs.
    sendDefaultPii: false,

    beforeSend(event) {
      return scrubEvent(event);
    },
  });
}
