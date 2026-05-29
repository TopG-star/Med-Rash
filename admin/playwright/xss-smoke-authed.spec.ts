import { expect, test } from "@playwright/test";

/**
 * Slice B8 — XSS smoke suite (authenticated routes).
 *
 * These tests cover the surfaces called out in the security plan:
 *   - nickname (participant context — see Flutter widget test for this)
 *   - host_name (admin sessions create + render)
 *   - quiz title (admin quiz-bank create + render)
 *   - question prompt (admin quiz-bank question create + render)
 *   - admin user name (admin-users invite + render)
 *
 * They are all skipped until the admin auth fixture lands.
 *
 * Open design questions documented in playwright/README.md:
 *   1. Real Supabase test project vs mock (`@supabase/ssr` is hard to mock cleanly).
 *   2. How to seed an allowlisted admin row without leaking creds.
 *   3. Whether to drive the OTP flow once and persist storageState, or
 *      directly mint both cookies (Supabase auth + `medrash-admin-session`
 *      from `admin-session-cookie.ts`) in a test-only API route gated by env.
 *
 * Once the fixture lands, remove the `test.describe.skip` and wire each
 * test up to the corresponding admin form + render path.
 */

test.describe.skip("XSS smoke — authenticated surfaces (pending auth fixture)", () => {
  test("host_name with XSS payload renders as text on sessions page", async () => {
    // 1. POST /sessions create with host_name = '<script>...'
    // 2. Visit /sessions, find the row, assert text content matches payload
    // 3. Assert no <script> element injected
  });

  test("quiz title with XSS payload renders as text on quiz-bank", async () => {
    // Same shape against /quiz-bank create + list.
  });

  test("question prompt with XSS payload renders as text", async () => {
    // /quiz-bank/<id>/questions create + render.
  });

  test("admin user display name with XSS payload renders as text", async () => {
    // /admin-users invite + list render.
  });
});
