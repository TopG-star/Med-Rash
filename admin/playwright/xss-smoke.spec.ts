import { expect, test } from "@playwright/test";

/**
 * Slice B8 — XSS smoke suite (unauthenticated routes).
 *
 * Routes covered here are in the middleware's PUBLIC_PATHS set, so they
 * render without Supabase env or an admin session. The test value is
 * regression detection: if someone replaces JSX text rendering with
 * `dangerouslySetInnerHTML` or innerHTML for any of these surfaces, these
 * tests catch it.
 *
 * Authenticated XSS surfaces (quiz title, host_name, question prompt,
 * admin user name) live in xss-smoke-authed.spec.ts and are skipped until
 * the admin auth fixture lands. See playwright/README.md.
 */

const XSS_SCRIPT_PAYLOAD = "<script>window.__xssTriggered=true;</script>";
const XSS_IMG_PAYLOAD = '<img src=x onerror="window.__xssTriggered=true">';
const XSS_SVG_PAYLOAD = "<svg onload=\"window.__xssTriggered=true\">";
const PAYLOADS = [XSS_SCRIPT_PAYLOAD, XSS_IMG_PAYLOAD, XSS_SVG_PAYLOAD];

test.describe("XSS smoke — /denied page", () => {
  for (const payload of PAYLOADS) {
    test(`reason='${payload.slice(0, 24)}…' is not executed or injected as an element`, async ({
      page,
    }) => {
      // Track any dialog the page tries to open — alert(1) must never fire.
      let dialogFired = false;
      page.on("dialog", async (dialog) => {
        dialogFired = true;
        await dialog.dismiss();
      });

      await page.goto(`/denied?reason=${encodeURIComponent(payload)}`);

      // The page must not have executed the payload.
      const xssFlag = await page.evaluate(
        () =>
          (window as unknown as { __xssTriggered?: boolean }).__xssTriggered ??
          false,
      );
      expect(xssFlag).toBe(false);
      expect(dialogFired).toBe(false);

      // The unknown reason key falls back to the allowlist copy, so the
      // payload string must not appear in the DOM at all.
      const body = (await page.locator("body").textContent()) ?? "";
      expect(body).not.toContain(payload);

      // Defence-in-depth: assert no element bearing the payload's
      // signature was injected. We can't blanket-count `body script`
      // because Next.js inlines RSC/runtime scripts there in production;
      // instead, match the payload signatures directly.
      const injectedScripts = await page
        .locator('body script[src="x"], body script:has-text("__xssTriggered")')
        .count();
      expect(injectedScripts).toBe(0);
      const onerrorAttrs = await page
        .locator("body [onerror], body [onload]")
        .count();
      expect(onerrorAttrs).toBe(0);
    });
  }

  test("known reason key renders its mapped copy as text", async ({ page }) => {
    await page.goto("/denied?reason=role");
    await expect(page.getByText(/Owner-only/i)).toBeVisible();
  });
});

test.describe("XSS smoke — /login page", () => {
  for (const payload of PAYLOADS) {
    test(`next='${payload.slice(0, 24)}…' is sanitised to /dashboard`, async ({
      page,
    }) => {
      let dialogFired = false;
      page.on("dialog", async (dialog) => {
        dialogFired = true;
        await dialog.dismiss();
      });

      await page.goto(`/login?next=${encodeURIComponent(payload)}`);

      const xssFlag = await page.evaluate(
        () =>
          (window as unknown as { __xssTriggered?: boolean }).__xssTriggered ??
          false,
      );
      expect(xssFlag).toBe(false);
      expect(dialogFired).toBe(false);

      // The page validates `next` must start with "/"; otherwise it defaults
      // to /dashboard. The hidden form input therefore holds /dashboard, NOT
      // the payload — even before considering JSX escaping.
      const hiddenNext = page.locator('input[type="hidden"][name="next"]');
      await expect(hiddenNext).toHaveValue("/dashboard");

      const injectedScripts = await page.locator("body script[src=x]").count();
      expect(injectedScripts).toBe(0);
    });
  }

  test("next=/safe/path is preserved verbatim in the hidden input", async ({
    page,
  }) => {
    await page.goto("/login?next=%2Fsessions");
    const hiddenNext = page.locator('input[type="hidden"][name="next"]');
    await expect(hiddenNext).toHaveValue("/sessions");
  });

  test("login form renders the work-email field", async ({ page }) => {
    await page.goto("/login");
    await expect(page.locator('input[name="email"][type="email"]')).toBeVisible();
  });
});
