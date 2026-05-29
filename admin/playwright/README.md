# Playwright suite — `admin/playwright/`

Slice B8 of [`docs/security-hardening-plan.md`](../../docs/security-hardening-plan.md). XSS regression suite for the admin Next.js portal.

## Run locally

From `admin/`:

```bash
# One-time: download the Chromium browser bundle
npx playwright install --with-deps chromium

# Run the full suite (boots `next dev` on :3000 automatically)
npx playwright test

# Run only the unauth smokes
npx playwright test xss-smoke.spec.ts

# Open the HTML report after a failed run
npx playwright show-report
```

CI runs the same command via `.github/workflows/ci.yml` (job: `playwright`).

## Test layout

| File | Status | Purpose |
|---|---|---|
| `xss-smoke.spec.ts` | **Active** | Unauthenticated routes (`/login`, `/denied`) — query param echo + form-field hidden value. Catches the day someone replaces JSX text with `dangerouslySetInnerHTML`. |
| `xss-smoke-authed.spec.ts` | **Skipped** | Authenticated surfaces: `host_name`, `quiz title`, `question prompt`, admin user display name. Pending auth fixture (see below). |

## Pending — admin auth fixture

The skipped suite needs a way to log in as an admin without going through the email OTP flow. Three options, in order of preference:

1. **Test-only API route + cookie mint** (preferred for hermetic CI). Add an env-gated route (e.g. `/api/test/login`, only registered when `ALLOW_TEST_AUTH=1`) that signs an `medrash-admin-session` cookie via `signAdminSessionCookie` from [`admin/src/lib/admin-session-cookie.ts`](../src/lib/admin-session-cookie.ts) AND mints a Supabase auth cookie for a seeded test user. Cleanest CI story but adds production-code surface gated by an env flag.

2. **Real Supabase test project + `storageState`** (cleanest but slowest). Stand up a dedicated Supabase project for tests; drive the OTP flow once via a global setup; persist the resulting cookies to `playwright/.auth/admin.json`; reuse via `use: { storageState: ... }`. Requires a real OTP delivery target (an email inbox the test can read, e.g. a `+playwright` Gmail alias with IMAP).

3. **Per-test cookie injection** (fragile). Hard-code a fixed test secret + pre-signed cookie blob. Breaks the moment session shape changes; not recommended.

When the fixture lands, remove `test.describe.skip(...)` in [`xss-smoke-authed.spec.ts`](xss-smoke-authed.spec.ts) and replace each TODO body with the corresponding create + render + assert flow.

## Why these tests instead of unit tests for XSS

React's JSX escapes by default; this is the actual mitigation. The regression risk is a future commit introducing `dangerouslySetInnerHTML` or raw DOM APIs with untrusted input. A full-browser test catches this whether the unsafe sink is in server-rendered HTML, client-hydrated React, or any future middleware/layout transform. A unit test of the component catches it only at one layer.

Trade-off: Playwright suites are slower than unit tests. We mitigate this by keeping the suite small and parallel, and running it as a separate CI job that can fail independently.
