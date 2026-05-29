import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";

// Slice A4 — Edge security headers (Next.js framework layer).
// These headers MUST mirror the `[[headers]]` block in the repo-root
// `netlify.toml`. Both layers exist so a drift in either configuration
// cannot silently un-secure the admin app.
//
// CSP ships as `Content-Security-Policy-Report-Only` on first deploy;
// after ~24h of clean browsing the key flips to `Content-Security-Policy`
// (must change in both this file AND `netlify.toml` in the same commit).
//
// Slice B7 — connect-src allowance for Sentry's browser SDK to POST
// envelopes to its public ingest endpoint (`https://<region>.ingest.sentry.io`
// and `https://<region>.ingest.us.sentry.io`). Without these origins the
// browser blocks every Sentry event with a CSP violation.
const ADMIN_CSP_DIRECTIVES = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self'",
  "connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.ingest.sentry.io https://*.ingest.us.sentry.io https://ingesteer.services-prod.nsvcs.net",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join("; ");

const SECURITY_HEADERS = [
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()",
  },
  { key: "Content-Security-Policy", value: ADMIN_CSP_DIRECTIVES },
];

const nextConfig: NextConfig = {
  async headers() {
    return [
      {
        source: "/:path*",
        headers: SECURITY_HEADERS,
      },
    ];
  },
};

// Slice B7 — Sentry build-time wrapper.
//
// `withSentryConfig` performs source-map upload to Sentry, injects the
// release identifier into the bundle, and auto-instruments the Next.js
// build. Source-map upload is gated on SENTRY_AUTH_TOKEN being present so
// local + CI builds without Sentry credentials still succeed.
//
// `tunnelRoute` proxies SDK ingest requests through /monitoring on our own
// origin, which means the CSP connect-src allowance for *.ingest.sentry.io
// is a belt-and-braces fallback for when the tunnel is disabled by an env
// override or fails to deploy.
export default withSentryConfig(nextConfig, {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  authToken: process.env.SENTRY_AUTH_TOKEN,
  silent: !process.env.CI,
  widenClientFileUpload: true,
  tunnelRoute: "/monitoring",
  disableLogger: true,
  automaticVercelMonitors: false,
  reactComponentAnnotation: { enabled: false },
  sourcemaps: {
    disable: !process.env.SENTRY_AUTH_TOKEN,
  },
});
