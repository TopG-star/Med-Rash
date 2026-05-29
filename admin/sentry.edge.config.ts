/**
 * Slice B7 — Edge runtime Sentry init.
 *
 * Loaded by instrumentation.ts when NEXT_RUNTIME === "edge". Covers the
 * admin middleware (session timeout enforcement from B1).
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
    sendDefaultPii: false,

    beforeSend(event) {
      return scrubEvent(event);
    },
  });
}
