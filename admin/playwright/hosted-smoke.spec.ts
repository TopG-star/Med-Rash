import { expect, test } from "@playwright/test";

/**
 * P0.6 — hosted contract smoke.
 *
 * Pings public function endpoints on a real deployed admin origin to lock
 * in the request/response contract that the rest of the stack depends on.
 * Designed to be safe to run against production: every call is read-only
 * or guaranteed-failure (401/400 paths); nothing is created.
 *
 * Skipped unless `MEDRASH_HOSTED_BASE_URL` is set. Example:
 *
 *   $env:MEDRASH_HOSTED_BASE_URL = "https://medrash-admin.netlify.app"
 *   npx --no-install playwright test playwright/hosted-smoke.spec.ts
 *
 * The local `webServer` started by playwright.config.ts is NOT used for
 * this spec; it talks straight to the hosted origin. Run the existing
 * xss-smoke spec against localhost as usual.
 */

const HOSTED_BASE_URL = process.env.MEDRASH_HOSTED_BASE_URL;

test.describe("hosted contract smoke", () => {
  test.skip(
    !HOSTED_BASE_URL,
    "Set MEDRASH_HOSTED_BASE_URL to the deployed admin origin to run.",
  );

  test("/.netlify/functions/health returns 200 JSON", async ({ request }) => {
    const res = await request.get(`${HOSTED_BASE_URL}/.netlify/functions/health`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body).toMatchObject({ ok: true });
  });

  test("/.netlify/functions/quiz-list rejects unauthenticated callers", async ({
    request,
  }) => {
    const res = await request.get(
      `${HOSTED_BASE_URL}/.netlify/functions/quiz-list`,
    );
    // Either 401 (missing bearer) or 403 (allowlist) is acceptable; the
    // contract is "does not leak the catalogue without a session".
    expect([401, 403]).toContain(res.status());
  });

  test("/.netlify/functions/session-resolve rejects empty body with 4xx", async ({
    request,
  }) => {
    const res = await request.post(
      `${HOSTED_BASE_URL}/.netlify/functions/session-resolve`,
      {
        data: {},
        headers: { "content-type": "application/json" },
      },
    );
    expect(res.status()).toBeGreaterThanOrEqual(400);
    expect(res.status()).toBeLessThan(500);
  });

  test("admin root ships CSP + HSTS headers", async ({ request }) => {
    const res = await request.get(`${HOSTED_BASE_URL}/`, {
      maxRedirects: 0,
      // The unauth root will 3xx to /login; we want the headers regardless.
      failOnStatusCode: false,
    });
    const headers = res.headers();
    expect(
      headers["content-security-policy"] ??
        headers["content-security-policy-report-only"],
    ).toBeTruthy();
    expect(headers["strict-transport-security"]).toMatch(/max-age=\d+/);
    expect(headers["x-frame-options"]?.toLowerCase()).toBe("deny");
    expect(headers["x-content-type-options"]?.toLowerCase()).toBe("nosniff");
  });
});
