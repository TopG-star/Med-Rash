/**
 * Slice B7 — Client-side telemetry (server + edge runtimes).
 *
 * Next.js 16 calls register() once per runtime (nodejs / edge). We
 * conditionally import the runtime-specific Sentry config so an Edge
 * deployment does not pull in Node-only modules.
 *
 * When SENTRY_DSN is empty, Sentry.init() inside the imported configs is a
 * no-op — safe to merge before the DSN is provisioned.
 */
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    // P0.3 \u2014 fail-fast on missing prod secrets. No-op in dev / during
    // `next build`; throws a single human-readable error otherwise.
    const { validateProductionEnv } = await import("./src/lib/env-validation");
    validateProductionEnv();
    await import("./sentry.server.config");
  }

  if (process.env.NEXT_RUNTIME === "edge") {
    await import("./sentry.edge.config");
  }
}

export { captureRequestError as onRequestError } from "@sentry/nextjs";
