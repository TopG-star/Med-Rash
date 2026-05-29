import { defineConfig, devices } from "@playwright/test";

/**
 * Slice B8 — XSS smoke suite.
 *
 * Unauthenticated tests run in CI on every PR (see .github/workflows/ci.yml).
 * Authenticated tests are skipped until the admin auth fixture lands; see
 * playwright/README.md for the design + open questions.
 */
export default defineConfig({
  testDir: "./playwright",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://127.0.0.1:3000",
    trace: "on-first-retry",
    actionTimeout: 10_000,
    navigationTimeout: 30_000,
  },
  webServer: process.env.PLAYWRIGHT_SKIP_WEBSERVER
    ? undefined
    : {
        // `next start` after a prior `next build` — the production server
        // uses far less memory than `next dev` (dev mode + the Sentry
        // build wrapper from B7 can blow past Node's default 4GB heap).
        // Build runs in the same command so `npm run e2e` is self-contained.
        command: "npm run build && npm run start -- --port 3000 --hostname 127.0.0.1",
        url: "http://127.0.0.1:3000",
        reuseExistingServer: !process.env.CI,
        timeout: 300_000,
        // Build + middleware need Supabase env to satisfy `supabase-ssr.readEnv()`.
        // The unauth XSS tests hit /login and /denied which the middleware
        // marks PUBLIC, but supabase-ssr still validates env at import-time.
        // Fake values are fine: the tests never trigger a real DB round-trip.
        // SENTRY_DSN left empty so the SDK no-ops (B7 posture).
        env: {
          NODE_ENV: "production",
          SUPABASE_URL: "http://127.0.0.1:54321",
          SUPABASE_ANON_KEY: "playwright-fake-anon-key",
          SUPABASE_SERVICE_ROLE_KEY: "playwright-fake-service-role-key",
          MEDRASH_ADMIN_SESSION_SECRET:
            "playwright-fake-admin-session-secret-32+chars-long",
          MEDRASH_DEVICE_TOKEN_SECRET:
            "playwright-fake-device-token-secret-32+chars-long",
          MEDRASH_TURNSTILE_SECRET: "playwright-fake-turnstile-secret",
        },
      },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
