# MedRash Security Hardening — Implementation Plan & Status

> **Single source of truth** for security work kicked off May 2026 following the MECE security review.
> Update the checkboxes as work lands. Add new decisions to the **Decisions Log** at the bottom.
> Companion to [docs/ui-overhaul-plan.md](ui-overhaul-plan.md) — same checkbox + verification discipline.

---

## 0. Direction (LOCKED)

**Posture:** treat MedRash as a hosted, multi-org, internationally-deployed medical CME platform.
**Benchmarks** every item maps to: **ISO/IEC 27001:2022 + 27002:2022**, **NIST CSF 2.0**, **OWASP ASVS 4.0.3**, **OWASP Top 10 (2021)**, **GDPR Art. 5/13/14/15/17/20/25/30/32/33/34/35/37**, **SOC 2 Common Criteria**, **HIPAA Security Rule §164.308–312** (medical-data adjacent).
**Discipline:** surgical commits, per-item verification report (workspace + mode + PASS/SKIP/FAIL), no `--no-verify`, no `-f` pushes.

### MECE security pillars (locked)

```
MedRash Security
├── 1. Identity & Access Management   (who is the requester, what may they do)
├── 2. Data Protection                (confidentiality of data at rest, in transit, in use)
├── 3. Application Surface            (input validation, output encoding, business-logic integrity)
├── 4. Network & Transport            (TLS, CORS, security headers, edge controls)
├── 5. Operational Security           (secrets, supply chain, build/CI, change mgmt)
├── 6. Observability & Audit          (logging, monitoring, alerting, forensics)
├── 7. Resilience & Abuse Prevention  (rate-limiting, bot defense, DoS, backup/restore)
└── 8. Governance & Compliance        (policies, threat model, GDPR/ISO/HIPAA, IR, vendor mgmt)
```

> Anything outside these 8 pillars (physical site security, contributor laptop hygiene, payroll IT) is out of scope for the application security plan and belongs to organisational IT policy.

---

## 1. Severity & status conventions

- 🔴 **Critical** — concrete attack path or compliance blocker; ship before next external pilot or any EU traffic.
- 🟡 **Moderate** — closes a gap auditors will flag; ship before SOC 2 / ISO 27001 readiness exercise.
- 🟢 **Minor** — defence-in-depth or polish; ship pre-scale.

Status flags per item: `[ ]` not started · `[~]` in progress · `[x]` complete · `[!]` blocked · `[-]` deferred (record why in Decisions Log).

Each item, once complete, MUST carry a **Verification block** with:

- Workspace path (e.g. `c:\Users\USER\Desktop\Personal\medRash`).
- Command mode (`local` / `hosted` / `auto`).
- One PASS/SKIP/FAIL line per executed check (typecheck, tests, lint, manual smoke, migration `db push`).
- Linked file paths edited.

---

## 2. Roadmap blocks (sequenced)

Three blocks. Items inside a block can be parallelised; blocks themselves are sequential because later blocks assume earlier primitives.

```
Block A  (pre-international-pilot must-haves)        ── ~1–2 wk focused work
Block B  (pre-SOC2 / ISO readiness must-haves)        ── ~4–8 wk
Block C  (pre-scale / second customer / hospital RFP) ── ongoing
```

---

## 3. Block A — pre-international-pilot must-haves

> Goal: remove every concrete day-one attack path a pen-tester would hit. Nothing in this block is optional before a second customer or EU traffic.

### Slice A1 🔴 — Persist OTP + per-IP rate limit in Postgres *(Pillars 1 & 7)*

**Problem solved:** in-memory per-function-instance lockout is bypassed by horizontal scale (different cold starts).

**Sub-tasks**

- [x] New migration `supabase/migrations/013_auth_rate_limit.sql` creating `app.auth_rate_limit` (key text pk, window_started_at timestamptz, attempt_count int, locked_until timestamptz nullable). Partial index on `locked_until` for sweep visibility. RLS service-role only. Atomic plpgsql function `app.enforce_rate_limit(p_key, p_limit, p_window_seconds, p_lockout_seconds)` + `app.reset_rate_limit(p_key)`.
- [x] New shared module `admin/src/lib/rate-limit.ts` (importable from both Next server actions and Netlify functions via `../../src/lib/rate-limit`) exporting `enforceRateLimit`, `resetRateLimit`, `rateLimitConfig`, `formatLockoutMessage`. Identifiers are SHA-256 hashed before storage (no raw email/IP at rest).
- [x] Wired into `admin/src/app/login/actions.ts` — `requestOtpAction` (`auth_otp_request`, 5/15min) and `verifyOtpAction` (`auth_otp_verify`, 5/15min). In-memory map removed.
- [x] Wired into `admin/netlify/functions/recover-request.ts` (`recover_otp_request`, 3/15min) and `recover-verify.ts` (`recover_otp_verify`, 5/15min, reset on success).
- [x] Unit tests in `admin/src/lib/rate-limit.test.ts` (7 tests: first hit allowed, Nth hit denied, lockout respected, window reset, reset clears key, identifier hashing, case/whitespace normalization).

**Files touched:** `supabase/migrations/013_auth_rate_limit.sql` (new), `admin/src/lib/rate-limit.ts` (new), `admin/src/lib/rate-limit.test.ts` (new), `admin/src/app/login/actions.ts`, `admin/netlify/functions/recover-request.ts`, `admin/netlify/functions/recover-verify.ts`.

**Verification:** typecheck PASS (`npx tsc --noEmit`, exit 0) · vitest PASS (31/31, including 7 new rate-limit tests) · `supabase db push` PENDING (user to run against hosted DB) · manual 429-on-6th-wrong-OTP across fresh instance PENDING (requires hosted deploy).

**Standards:** ISO 27002 §5.15, 5.17, 8.5 · OWASP ASVS V2.2 · NIST CSF PR.AA-3.

---

### Slice A2 🔴 — Replace static gate key with per-device signed tokens *(Pillar 1)*

**Problem solved:** `x-medrash-gate-key` is a static shared bearer; leak from any participant build = full access to every participant endpoint.

**Sub-tasks**

_Phase 1 — backend dual-path (this commit):_

- [x] Define token shape. Implemented as `${base64url(payloadJsonString)}.${base64url(HMAC-SHA256(secret, payloadB64))}` — same HMAC inputs as spec, but a structured payload (`{ v, did, pid, iat, exp, n }`) so verify can return parsed claims directly. TTL: 24h sliding; refresh window opens 1h before expiry.
- [x] New shared module `admin/netlify/functions/_shared/device-token.ts` — exports `mintDeviceToken()`, `verifyDeviceToken()`, `extractBearerToken()`, plus typed verify-error codes.
- [x] New endpoint `admin/netlify/functions/device-token.ts` — accepts `{ deviceInstallId, participantId? }`, gated (transitional) by the legacy gate key, returns `{ token, issuedAt, expiresAt, refreshAfter }`.
- [x] New shared wrapper `admin/netlify/functions/_shared/participant-auth.ts` — `requireParticipantAuth()` accepts `Authorization: Bearer <token>` first; if absent, falls back to the legacy gate key when `MEDRASH_GATE_KEY_FALLBACK !== "false"` (default on during Phase 1+2).
- [x] All 8 participant Netlify functions migrated to `requireParticipantAuth` (`profile-sync`, `quiz-list`, `leaderboard`, `ranked-eligibility`, `attempt-submit`, `recover-request`, `recover-verify`, `session-resolve`). A1 rate-limit logic on `recover-*` preserved.

_Phase 2 — Flutter switchover (this commit):_

- [x] Update Flutter `app/lib/core/infra/medrash_http_client.dart` to accept an optional `tokenProvider` callback; when it yields a non-empty token the request gets `Authorization: Bearer <token>`. Gate key is still attached on every request during Phase 2 so the server-side fallback in `_shared/participant-auth.ts` keeps working if the token store has not minted yet.
- [x] New `app/lib/core/infra/device_token_store.dart` — minimal custodian that mints via `POST /device-token` (using the legacy gate key for the bootstrap call), persists `{token, expiresAt, refreshAfter}` to SharedPreferences, single-flights concurrent mints, refreshes once `now >= refreshAfter`, falls back to the cached token if mint fails but the cache is still pre-expiry. Returns `null` on full failure so the HTTP client simply omits the bearer header (server falls back to gate key).
- [x] Wire `DeviceTokenStore` into `app/lib/core/di/init_core.dart` ahead of `MedRashHttpClient` and pass `tokenProvider: () => getIt<DeviceTokenStore>().currentToken()`.
- [x] Document rotation procedure + new env vars (`MEDRASH_DEVICE_TOKEN_SECRET`, `MEDRASH_GATE_KEY_FALLBACK`) in `docs/admin-surfaces.md` §6.3 + §6.4.

_Phase 3a — kill the fallback (this commit):_

- [x] Verify `MEDRASH_GATE_KEY_FALLBACK=false` in Netlify env. **Confirmed by user — pilot session ran clean on bearer-only traffic.**
- [x] Remove the gate-key fallback branch from `admin/netlify/functions/_shared/participant-auth.ts`. Bearer-only. The `MEDRASH_GATE_KEY_FALLBACK` env var is now ignored. `participant-auth.test.ts` shrunk from 6 → 5 tests (dropped the two fallback paths, added one "ignores the env var" assertion).
- [x] `_shared/gate.ts` kept in place because `/device-token` still uses it for bootstrap. Deletion deferred to Phase 3b once Turnstile lands.

_Phase 3b — replace bootstrap + delete gate.ts (this commit, dual-path):_

- [x] `admin/netlify/functions/_shared/turnstile.ts` (new) — verifies a Cloudflare Turnstile token via `https://challenges.cloudflare.com/turnstile/v0/siteverify` using `MEDRASH_TURNSTILE_SECRET`. Returns structured `{ok, errorCodes, errorMessage}`. Honors `MEDRASH_TURNSTILE_BYPASS_TOKEN` env var for hosted smoke-tests + CI.
- [x] `admin/netlify/functions/_shared/rate-limit-bucket.ts` (new) — in-memory token bucket keyed by `${remoteIp}::${deviceInstallId}`. Per-function-instance scope (sticky-warm sufficient for pilot; would need Upstash/Redis for true distributed defense). Default 5 burst / 10 per minute, overridable via `MEDRASH_DEVICE_TOKEN_RATE_BURST` and `MEDRASH_DEVICE_TOKEN_RATE_REFILL_PER_MIN`. Hard bypass via `MEDRASH_DEVICE_TOKEN_RATE_DISABLED=true`.
- [x] `admin/netlify/functions/device-token.ts` rewired — **dual-path**. If `turnstileToken` is present in the JSON body, verify + rate-limit; a present-but-invalid token returns 401 `TURNSTILE_REJECTED` (strict, mirroring the 3a participant-auth ordering). If `turnstileToken` is absent, fall back to the legacy `x-medrash-gate-key` header. Rate-limit breach returns 429 `RATE_LIMITED` with a `retry-after` header. **`_shared/gate.ts` is still in place** — deletion is deferred to Phase 3c so a broken Turnstile widget can't brick the pilot.
- [x] Flutter web Turnstile integration — `app/web/index.html` ships a vanilla-JS shim (`window.medrashTurnstileExecute(siteKey)`) that lazy-loads the Turnstile script, renders an invisible widget into a hidden host div, and resolves a single-use token per call. Hard 12s timeout ceiling so a hung widget never blocks mint forever.
- [x] Flutter Dart side — `app/lib/core/infra/turnstile_token_provider.dart` is an abstract interface with conditional imports: `turnstile_token_provider_stub.dart` for non-web (always returns null) and `turnstile_token_provider_web.dart` for web (calls the JS shim via `dart:js_interop`). `StaticTurnstileTokenProvider` is exposed for tests. New `--dart-define=MEDRASH_TURNSTILE_SITE_KEY=…` reads into `AppConfig.turnstileSiteKey`.
- [x] `DeviceTokenStore` accepts an optional `turnstileTokenProvider`; when configured, awaits a token before mint, includes it in the body as `turnstileToken`, and logs+continues on provider failure (server then falls back to gate key). `init_core.dart` registers the provider as a lazy singleton ahead of `DeviceTokenStore`.

_Phase 3c — strip the gate key entirely (this commit, after one clean Phase 3b pilot session):_

- [x] Removed the gate-key fallback branch from `device-token.ts`. `turnstileToken` is now a required body field; missing token returns 400 `BAD_REQUEST`. Rate-limit + Turnstile verify run unconditionally.
- [x] Deleted `admin/netlify/functions/_shared/gate.ts`.
- [x] Removed `MEDRASH_GATE_API_KEY` from the Netlify env contract (Netlify dashboard entry can be deleted after this deploy lands).
- [x] Dropped `_gateApiKey` field from Flutter `DeviceTokenStore`, `MedRashHttpClient`, `AppConfig`. `init_core.dart` rewired to omit the param.
- [x] Dropped the `x-medrash-gate-key` header attachment in `MedRashHttpClient._buildHeaders` and from the CORS `access-control-allow-headers` lists in `_shared/http.ts` and `health.ts`.
- [x] `app/scripts/build-web.sh` no longer requires `MEDRASH_GATE_API_KEY`; instead requires `MEDRASH_TURNSTILE_SITE_KEY` as a hard `:?` env check.
- [x] `participant-auth.test.ts` rewritten to no longer set `MEDRASH_GATE_API_KEY` env; legacy gate-key header on requests is now treated as a stale stray header (still 401s, as expected).

**Files touched:** `admin/netlify/functions/_shared/device-token.ts` (new), `admin/netlify/functions/_shared/device-token.test.ts` (new), `admin/netlify/functions/_shared/participant-auth.ts` (new), `admin/netlify/functions/_shared/participant-auth.test.ts` (new), `admin/netlify/functions/device-token.ts` (new), 8 participant function files (1-line import + 3-line call-site swap each). Phase 2/3 will additionally touch `app/lib/core/...` and `docs/admin-surfaces.md`.

**Verification (Phase 1 — 2025-01, workspace `c:\Users\USER\Desktop\Personal\medRash\admin`):**

- typecheck — `npx tsc --noEmit` → exit 0. **PASS**
- vitest — `npx vitest run` → 5 files / 48 tests pass (rate-limit 7, device-token 11, callback-handler 15, participant-auth 6, admin-user-session 9). **PASS**
- forged-token 401 — covered by `device-token.test.ts` (tampered payload + tampered signature both return `DEVICE_TOKEN_BAD_SIGNATURE` 401) and `participant-auth.test.ts` (invalid bearer rejected without falling back). **PASS**
- expired-token re-mint — covered by `device-token.test.ts` ("rejects an expired token" → `DEVICE_TOKEN_EXPIRED`). **PASS**
- legacy-fallback opt-out — covered by `participant-auth.test.ts` (`MEDRASH_GATE_KEY_FALLBACK=false` makes a gate-key-only request return 401). **PASS**
- Flutter `flutter analyze` / `flutter test` — **PASS (Phase 2, 2026-05).** `flutter analyze` → No issues found. `flutter test` → 178/178 pass (incl. 6 new `device_token_store_test.dart` cases: cold-mint cache, refresh-after expiry, mint-failure no-cache → null, mint-failure with cache → cached token, `clear()` wipes prefs, concurrent calls dedupe into one mint).
- Phase 3a typecheck / vitest (workspace `c:\Users\USER\Desktop\Personal\medRash\admin`) — **PASS.** `npm run typecheck` → exit 0; `npm test` → 5 files / 47 tests pass (was 48; net −3 fallback tests, +2 bearer-only tests on `participant-auth.test.ts`).
- Phase 3a hosted smoke (Flutter pilot still 200s, `/device-token` mint still 200s) — **PASS (user-confirmed 2026-05-27).** No regressions observed after redeploy with `MEDRASH_GATE_KEY_FALLBACK=false`.
- Phase 3b typecheck / vitest (workspace `c:\Users\USER\Desktop\Personal\medRash\admin`) — **PASS.** `npm run typecheck` → exit 0; `npm test` → 7 files / 66 tests pass (was 47; +13 `turnstile.test.ts`, +6 `rate-limit-bucket.test.ts`).
- Phase 3b Flutter `flutter analyze` / `flutter test` (workspace `c:\Users\USER\Desktop\Personal\medRash\app`) — **PASS.** `flutter analyze` → No issues found; `flutter test` → 180/180 pass (was 178; +2 new `device_token_store_test.dart` cases: sends `turnstileToken` when provider returns non-null, omits when null).
- Phase 3b hosted smoke (Turnstile challenge succeeds, `/device-token` rejects without Turnstile, rate limit kicks in after burst) — **PASS (user-confirmed 2026-05-28).** Pilot session ran clean on a Turnstile-only `/device-token` mint with `MEDRASH_TURNSTILE_SECRET` + `MEDRASH_TURNSTILE_SITE_KEY` set; no regressions.
- Phase 3c typecheck / vitest (workspace `c:\Users\USER\Desktop\Personal\medRash\admin`, mode local) — **PASS.** `npm run typecheck` → exit 0; `npm test` → 7 files / 66 tests pass (same count as 3b — same coverage now exercised against the Turnstile-only path).
- Phase 3c Flutter `flutter analyze` / `flutter test` (workspace `c:\Users\USER\Desktop\Personal\medRash\app`, mode local) — **PASS.** `flutter analyze` → No issues found; `flutter test` → 180/180 pass (same count as 3b; the gate-key-header assertion in `device_token_store_test.dart` was removed, the cold-mint test now asserts the request body shape only).
- Phase 3c hosted smoke (gate key fully removed, only Turnstile accepted; rejecting `x-medrash-gate-key`-only requests with 400) — **PASS (user-confirmed 2026-05-28).** `MEDRASH_GATE_API_KEY` deleted from Netlify env, Flutter web rebuilt with only `MEDRASH_FUNCTIONS_BASE_URL` + `MEDRASH_TURNSTILE_SITE_KEY` defines, redeployed; one full pilot session (login → quiz → leaderboard) ran clean.

**Standards:** ISO 27002 §5.16, 5.17, 8.2, 8.5 · OWASP ASVS V3.5, V6.2 · NIST CSF PR.AA-1, PR.AA-2.

---

### Slice A3 🔴 — Tighten RLS + view security_invoker *(Pillar 2)*

**Problem solved:** `app.sessions` is fully public-readable via anon key; `app.admin_users` has no RLS; leaderboard views inherit creator privileges.

**Sub-tasks**

- [x] New migration adding `with (security_invoker = true)` to `app.ranked_attempt_totals_all_time` and `app.ranked_attempt_totals_monthly` (shipped as `014_security_invoker_views.sql`).
- [x] New migration adding RLS policies for `app.admin_users` (shipped as `015_admin_users_rls.sql`):
  - `admin_users_service_role_all` (service_role).
  - `admin_users_self_select` (`auth.uid() = user_id`).
  - Deny everything else.
- [x] New migration tightening `app.sessions` RLS (shipped as `016_tighten_sessions_rls.sql`):
  - Drop `sessions_public_select` (`using (true)`).
  - **Deviation from spec:** the plan called for a narrow `sessions_anon_join_lookup` policy gated on `status in ('open','live')`, but `app.sessions` has no `status` column (lifecycle is `starts_at`/`ends_at`). All TS/Dart callers already use the service-role client (`session-resolve.ts`, `session-queries.ts`, `session-create.ts`, `reports-queries.ts`, `overview-queries.ts`; Flutter goes through `session-resolve` Netlify function), so we ship deny-by-default for anon rather than speculatively add a permissive `[starts_at, ends_at)` window policy with no consumer. Explicit `sessions_service_role_all` policy added for documentation.
  - Service-role keeps full access.
- [ ] Add `with (security_invoker = true)` as a **convention** to all future views; add a CONTRIBUTING note + lint-style grep check in CI (Block B Slice B6).
- [ ] Verify Flutter participant join flow + admin host page still resolve sessions correctly under the new policy (post-deploy hosted smoke).

**Files touched:** `supabase/migrations/0NN_*.sql` (2–3 files), `docs/admin-surfaces.md` §6 (RLS table refresh).

**Verification:** SQL drafted in `supabase/migrations/014_security_invoker_views.sql`, `015_admin_users_rls.sql`, `016_tighten_sessions_rls.sql` (3 files, idempotent — all `drop policy if exists` / `alter` statements safe to re-run) · static caller audit PASS (every TS/Dart reference to `app.sessions`, `app.admin_users`, and the two ranked views uses the service-role client; no anon callers will break) · `supabase db push` against hosted DB **PASS (user-confirmed 2026-05-29)** · hosted smoke (participant join → quiz → leaderboard + admin login + sessions + admin-users pages) **PASS (user-confirmed 2026-05-29).**

**Standards:** ISO 27002 §5.15, 8.3, 8.12 · OWASP ASVS V8.3 · GDPR Art. 25, 32 · NIST CSF PR.DS-5.

---

### Slice A4 🔴 — Edge security headers *(Pillar 4)*

**Problem solved:** no CSP / HSTS / X-Frame-Options means any XSS escalates to data exfiltration; admin can be clickjacked.

**Sub-tasks**

- [x] Define CSP for admin: `default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://*.supabase.co wss://*.supabase.co; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'`. Shipped as **report-only** in Phase 1 (current commit); flips to enforcing in Phase 2 after ~24h hosted observation. `wss://*.supabase.co` added to `connect-src` for Supabase Realtime.
- [x] Define CSP for participant Flutter web: `default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https://*.netlify.app https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; child-src blob: https://challenges.cloudflare.com; worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'`. Added beyond the plan baseline: `'wasm-unsafe-eval'` (CanvasKit), Cloudflare Turnstile origins (script + frame + child + connect), `https://*.netlify.app` (functions origin until pinned to a single hostname). Also shipped **report-only** in Phase 1.
- [x] Add headers to `netlify.toml` (root → admin) AND `app/netlify.toml` (Flutter web) AND `admin/next.config.ts` `async headers()` (defence-in-depth: Netlify edge + Next.js framework). Admin headers are duplicated across `netlify.toml` and `next.config.ts`; the two values are kept literally identical and must be edited together when flipping CSP from report-only to enforcing.
- [x] Headers to ship: `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()` for admin / `camera=(self), microphone=(), geolocation=(), payment=(), usb=()` for participant (camera scoped to participant origin for the QR scanner).
- [x] Phase 2 (after ~24h hosted observation with zero blocking CSP-Report-Only violations in console): rename both header keys from `Content-Security-Policy-Report-Only` → `Content-Security-Policy` in `netlify.toml`, `app/netlify.toml`, and `admin/next.config.ts` (3 edits, one commit). Redeploy. **Shipped 2026-05-29 (user authorized immediate flip, skipping the 24h observation window).**
- [ ] Run [securityheaders.com](https://securityheaders.com) against both deployed origins post-rollout; target grade **A** minimum. (Optional follow-up; not blocking A4 close-out.)

**Files touched:** root `netlify.toml`, `app/netlify.toml`, `admin/next.config.ts`, `docs/hosted-deploy.md` (record final header set), `docs/security-hardening-plan.md` (this file).

**Verification:** Phase 1 — admin `npm run typecheck` PASS · all 6 headers echo on every response. Phase 2 — admin `npm run typecheck` PASS · hosted smoke **PASS (user-confirmed 2026-05-29)**: admin full walk-through (dashboard → quiz-bank → sessions → reports → intelligence → admin-users) and participant full walk-through (QR/join → quiz → leaderboard) both clean with zero blocking CSP violations; Cloudflare Turnstile still mints; Supabase Realtime still connects.

**Standards:** ISO 27002 §8.20, 8.21, 8.22, 8.23 · OWASP ASVS V14.4, V14.5 · OWASP Secure Headers Project · NIST CSF PR.IR-1.

---

### Slice A5 🟢 — Auth + admin-action audit logs *(Pillar 6)*

**Problem solved:** no persistent record of who logged in, who failed, who edited what — fails ISO 27002 §8.15 and breach-investigation needs.

**Sub-tasks**

- [x] **Phase 1 (committed):** New migration `017_audit_logging_tables.sql` creating `app.auth_events` + `app.admin_audit` with service-role RLS, `expire_at` retention column (default `now() + 730 days`), and per-table indexes (`occurred_at desc`, `(event_type, occurred_at desc)`, `(user_id, occurred_at desc)`, `(actor_user_id, occurred_at desc)`, `(action, occurred_at desc)`, `(target_type, target_id, occurred_at desc)`, `expire_at` for cleanup). Event-type check constraint covers 10 types (added `otp_rate_limited` + `recover_rate_limited` vs original spec; dropped `session_refresh` per audit — it's atomic SSR cookie refresh, not a discrete event worth logging).
- [x] **Phase 1 (committed):** Shared module `admin/src/lib/audit.ts` exporting `logAuthEvent(client, input)` + `logAdminAction(client, input)` — both fire-and-forget, both SHA-256 hash email/IP/UA, both never throw. Single canonical module imported from both Next.js server actions and Netlify functions (same pattern as `admin/src/lib/rate-limit.ts`). 7-test vitest suite verifies hashing + PII non-persistence + fire-and-forget invariants.
- [x] **Phase 1 (committed):** Smoke wire-ins — `verifyOtpAction` (success / fail / rate-limited paths) + `session-create` (1 op).
- [x] **Phase 2 (committed):** Wired `logAuthEvent` into remaining auth surfaces: `requestOtpAction` (success + rate-limit + signInWithOtp error), `signOutAndRedirectAction` (captures userId from `getUser()` *before* signOut clears cookies), `getAdminSession` (allowlist deny — both `lookup_error` and `not_on_allowlist` / `inactive` paths), `recover-request` (success / rate-limited / profile-not-found / supabase-429 / otp-send-failed), `recover-verify` (success / rate-limited / otp-invalid / profile-not-found / recovery-conflict).
- [x] **Phase 2 (committed):** Wired `logAdminAction` into remaining admin-write surfaces: `quiz-bank-write` (all 7 ops — `create_quiz`, `update_quiz`, `deactivate_quiz`, `create_question`, `update_question`, `deactivate_question`, `bulk_create_questions`), `admin-users/actions.ts` (all 5 ops — `invite_admin`, `reinvite_admin`, `deactivate_admin`, `reactivate_admin`, `set_admin_role`), `onboarding/actions.ts` (`complete_onboarding`).
- [x] **Phase 3 (committed):** Scheduled retention cleanup — `admin/netlify/functions/audit-retention-purge.ts` scheduled via `netlify.toml [functions."audit-retention-purge"] schedule = "17 3 * * *"` (03:17 UTC daily, off-the-hour to dodge round-time cron pileups). Deletes from `app.auth_events` and `app.admin_audit` where `expire_at <= now()` using `.delete({ count: "exact" })` so the success log captures per-table row counts. Idempotent + service-role-keyed so manual invocation is safe but unnecessary.

**Files touched (phase 1):** `supabase/migrations/017_audit_logging_tables.sql` (new), `admin/src/lib/audit.ts` (new), `admin/src/lib/audit.test.ts` (new), `admin/src/app/login/actions.ts` (verifyOtpAction wire-in + `readClientHeaders` helper), `admin/netlify/functions/session-create.ts` (session_create wire-in).

**Files touched (phase 2):** `admin/src/app/login/actions.ts` (requestOtpAction + signOutAndRedirectAction wire-ins), `admin/src/lib/admin-session.ts` (`getAdminSession` allowlist deny + `readClientHeaders` helper), `admin/netlify/functions/recover-request.ts` (4 outcomes), `admin/netlify/functions/recover-verify.ts` (5 outcomes), `admin/netlify/functions/quiz-bank-write.ts` (7 ops), `admin/src/app/admin-users/actions.ts` (5 ops), `admin/src/app/onboarding/actions.ts` (1 op).

**Files touched (phase 3):** `admin/netlify/functions/audit-retention-purge.ts` (new), `netlify.toml` (schedule config).

**Verification phase 1+2:** typecheck PASS · vitest 73/73 PASS (+7 new in phase 1) · `supabase db push` PASS (2026-05-29, migration 017 applied by user) · hosted smoke PASS (2026-05-29, user-confirmed: triggered OTP verify + session create, both timelines populated).

**Verification phase 3:** typecheck PASS · hosted smoke PENDING (next 03:17 UTC tick — observe Netlify Functions log for `[audit-retention-purge] ok ...` line with counts, OR invoke manually via `curl -X POST https://medrash-admin.netlify.app/.netlify/functions/audit-retention-purge` to confirm `{ok: true, ...}` response).

**Standards:** ISO 27002 §8.15, 8.16, 8.17 · OWASP ASVS V7 · NIST CSF DE.AE-1..8, DE.CM-1 · SOC 2 CC7.2, CC7.3 · GDPR Art. 5(1)(f), 32(1)(b).

---

### Slice A6 🔴 — Centralized rate limiting on all 9 unprotected endpoints *(Pillar 7)*

**Problem solved:** 9 of 11 Netlify functions have zero rate limiting; gate-key holder (or its leak) can drain Supabase + Netlify spend.

**Sub-tasks**

- [ ] Extend `_shared/rate-limit.ts` from A1 with `scope` enum: `auth_otp`, `auth_verify`, `recover_otp`, `profile_sync`, `attempt_submit`, `ranked_eligibility`, `quiz_list`, `leaderboard`, `quiz_bank_write`, `session_create`.
- [ ] Per-scope defaults (tunable via env):
  - `attempt_submit`: 60 / 60s per participant_id, 600 / 60s per IP.
  - `profile_sync`: 30 / 60s per device.
  - `ranked_eligibility`: 120 / 60s per device.
  - `leaderboard` / `quiz_list`: 60 / 60s per IP.
  - `quiz_bank_write` / `session_create`: 30 / 60s per admin user_id.
- [ ] Wire into all 9 endpoints at the top of the handler, before any DB call.
- [ ] Standard 429 response: `{ error: 'rate_limited', retryAfterMs }` + `Retry-After` header.
- [ ] Emit `auth_events`-style log to a new `app.rate_limit_events` table (or reuse `app.auth_events` with a `'rate_limited'` event type — decide in implementation; default to reuse to avoid table sprawl).

**Files touched:** `admin/netlify/functions/_shared/rate-limit.ts` (extend), every participant + admin Netlify function under `admin/netlify/functions/`.

**Verification:** typecheck PASS · vitest PASS (per-scope limits hit & reset) · manual: hammer one endpoint past its cap, observe 429 with `Retry-After`; observe entries in audit table.

**Standards:** ISO 27002 §5.30, 8.6, 8.14 · OWASP ASVS V11.1 · NIST CSF PR.IR-2 · OWASP Top 10 A04 (Insecure Design).

---

### Slice A7 🔴 — Adopt zod for all Netlify function + server-action inputs *(Pillar 3)*

**Problem solved:** handwritten validators drift; new endpoints reinvent trim/length/enum checks; no single source of truth for input shapes.

**Sub-tasks**

- [ ] Add `zod` to `admin/package.json` dependencies (it has no transitive heavy deps and is already a Next.js norm).
- [ ] New folder `admin/src/lib/schemas/` (Next.js + functions can both import from here since Netlify functions transpile from the admin tree).
- [ ] One schema file per resource: `identity.ts`, `attempt.ts`, `session.ts`, `quiz.ts`, `recover.ts`, `leaderboard.ts`.
- [ ] Replace handwritten `parseIdentityInput`, `parseCreateSessionInput`, etc. with `Schema.safeParse(payload)`; surface field-level errors in 400 responses with `{ error: 'invalid_input', issues: [{ path, message }] }`.
- [ ] Keep server-side score recomputation in `attempt-submit.ts` intact — zod only validates shape, not business invariants.
- [ ] Generate TypeScript types via `z.infer<>` and remove duplicate hand-typed input interfaces.

**Files touched:** `admin/package.json` + `package-lock.json`, `admin/src/lib/schemas/*` (new), every Netlify function that takes a body, server actions in `admin/src/app/**/actions.ts`.

**Verification:** typecheck PASS · existing vitest PASS unchanged · new vitest PASS for each schema (happy path + 3 rejection paths per schema) · manual: post malformed JSON to `/attempt-submit`, see structured 400.

**Standards:** ISO 27002 §8.28 · OWASP ASVS V1.5, V5.1 · OWASP Top 10 A03 (Injection), A04 (Insecure Design).

---

### Block A close-out gate

Before marking Block A complete:

- [ ] All 7 slices verified PASS.
- [ ] `npm run typecheck`, `npm run test`, `npm run lint` PASS in `admin/`.
- [ ] `flutter analyze` and `flutter test` PASS in `app/`.
- [ ] Supabase Advisor lints: **0 critical, 0 SECURITY DEFINER view findings, 0 missing-RLS findings**.
- [ ] One end-to-end pilot dry-run: admin login → create session → participant scan QR → attempt → leaderboard, with audit + rate-limit + token-bound headers all observed.
- [ ] Decisions Log updated with one entry per slice noting any deviations.

---

## 4. Block B — pre-SOC2 / ISO 27001 readiness must-haves

> Goal: close every finding an auditor will flag during a SOC 2 Type I or ISO 27001 Stage 1 readiness exercise. Ship over 4–8 weeks after Block A.

### Slice B1 🟡 — TOTP MFA for `owner` role + session timeout policy *(Pillar 1)*
- [ ] Enable Supabase Auth TOTP factor; require enrollment on first `owner` login; deny privileged routes when factor missing.
- [ ] Document idle (30 min) + absolute (8 h) session timeout, enforced in middleware.
- [ ] Audit-log MFA enroll / use / disable.
- **Standards:** ISO 27002 §5.17, 8.5 · OWASP ASVS V2.7 · SOC 2 CC6.1.

### Slice B2 🟡 — pgcrypto column encryption for high-sensitivity PII *(Pillar 2)*
- [ ] Encrypt `app.users.email`, `app.users.full_name`, `app.admin_users.email` with Supabase Vault or pgcrypto (`pgp_sym_encrypt`).
- [ ] Keep a deterministic SHA-256 hash column for lookup-by-email (case-insensitive lower-hash) so unique constraints and recovery flow still work.
- [ ] Document key-management procedure + rotation cadence.
- **Standards:** ISO 27002 §5.12, 8.24 · GDPR Art. 32(1)(a) · HIPAA §164.312(a)(2)(iv).

### Slice B3 🟡 — GDPR data-subject endpoints *(Pillars 2 & 8)*
- [ ] `POST /api/me/export` (participant + admin) — returns full subject data as JSON + CSV in a signed download URL.
- [ ] `POST /api/me/delete` — soft-delete + queued hard-delete after 30-day grace, with audit log entry.
- [ ] Publish public privacy policy + Data Processing Agreement template under `docs/legal/`.
- **Standards:** GDPR Art. 17, 20, 28 · ISO 27002 §5.34.

### Slice B4 🟡 — CI hardening *(Pillar 5)*
- [ ] Extend `.github/workflows/` with a `ci.yml` running on PR + push: `npm run typecheck`, `npm run test`, `npm run lint` for admin; `flutter analyze`, `flutter test` for app.
- [ ] Add `security.yml`: `npm audit --omit=dev`, `osv-scanner`, `gitleaks`, GitHub secret scanning (free), Dependabot for npm + pub.
- [ ] Generate SBOM (`cyclonedx-npm`, `cyclonedx-flutter`) on release tag; attach to GitHub Release.
- **Standards:** ISO 27002 §8.8, 8.25, 8.28, 8.30 · NIST SSDF · SOC 2 CC8.1.

### Slice B5 🟡 — Threat model + incident response plan + vendor register *(Pillar 8)*
- [ ] 1-page STRIDE per surface in `docs/security/threat-model/` (admin-auth, participant-runner, host-live, recovery, leaderboard).
- [ ] Incident response runbook in `docs/security/incident-response.md` (severities, on-call, GDPR 72h breach template).
- [ ] Vendor register in `docs/security/vendor-register.md` (Supabase, Netlify, GitHub, font providers — risk, DPA on file, criticality).
- **Standards:** ISO 27001 §6.1.2, §16 · ISO 27002 §5.7, 5.19–5.30 · NIST CSF GV, RS · GDPR Art. 30, 33, 34, 35.

### Slice B6 🟡 — Backup/restore drill + DR runbook *(Pillar 7)*
- [ ] Confirm Supabase PITR cadence on current plan; document in `docs/security/dr-runbook.md`.
- [ ] Perform one quarterly restore-to-staging drill; record outcome.
- [ ] Document domain hijack + Netlify-org-lock + Supabase-project-suspend recovery paths.
- **Standards:** ISO 27002 §8.13, 8.14 · SOC 2 A1.2, A1.3.

### Slice B7 🟡 — Client-side telemetry *(Pillar 6)*
- [ ] Add Sentry (or equivalent) to admin Next.js and Flutter participant. PII scrubber on by default; bind release SHA.
- [ ] Define alerting thresholds (error-rate spike, auth-fail spike).
- **Standards:** ISO 27002 §8.15, 8.16 · NIST CSF DE.CM-1.

### Slice B8 🟡 — Frontend XSS smoke tests *(Pillar 3)*
- [ ] Playwright suite on admin: store `<script>alert(1)</script>` in nickname, host_name, quiz title, question prompt → assert rendered as text everywhere.
- [ ] Flutter integration test mirror.
- **Standards:** OWASP ASVS V5.3 · OWASP Top 10 A03.

---

## 5. Block C — pre-scale (≥ 10k users, second org, hospital RFP)

### Slice C1 🟢 — Multi-tenant isolation *(Pillar 2)*
- [ ] Add `tenant_id uuid not null` to every `app.*` table; backfill pilot tenant; tenant-scoped RLS.
- [ ] Tenant-aware admin sessions + audit + leaderboards.
- **Standards:** ISO 27002 §8.31 · SOC 2 CC6.6.

### Slice C2 🟢 — SIEM / centralized log shipping *(Pillar 6)*
- [ ] Ship Netlify + Supabase + Sentry logs to a SIEM (Logflare, Datadog, Elastic).
- **Standards:** ISO 27002 §8.15, 8.16.

### Slice C3 🟢 — Formal ISO 27001 ISMS kickoff *(Pillar 8)*
- [ ] Policies, Statement of Applicability, internal audit, management review cycle.
- **Standards:** ISO 27001 §4–10.

### Slice C4 🟢 — External penetration test *(Pillar 8)*
- [ ] Engage a CREST-accredited (or equivalent) testing firm; remediate findings before public launch.
- **Standards:** ISO 27002 §8.8 · SOC 2 CC4.1.

---

## 6. Standards traceability matrix

| Pillar | ISO 27002 controls | OWASP ASVS chapters | NIST CSF subcategories | GDPR articles | SOC 2 CC |
|---|---|---|---|---|---|
| 1. IAM | 5.15, 5.16, 5.17, 5.18, 8.2, 8.5 | V2, V3 | PR.AA-1..6 | 32 | CC6.1, CC6.2, CC6.3 |
| 2. Data Protection | 5.12, 5.13, 5.14, 5.33, 5.34, 8.10, 8.11, 8.12, 8.24 | V6, V8, V9 | PR.DS-1..5 | 5, 17, 20, 25, 32 | CC6.5, CC6.7 |
| 3. App Surface | 8.25, 8.26, 8.27, 8.28 | V1, V4, V5, V11, V13 | PR.PS-1..6 | 25, 32 | CC7.1 |
| 4. Network/Transport | 8.20, 8.21, 8.22, 8.23 | V12, V14 | PR.IR-1 | 32 | CC6.7 |
| 5. OpSec / Supply Chain | 5.20–5.23, 8.4, 8.8, 8.19, 8.25, 8.30 | V14 | PR.PS-1..6, SC-7 | 28, 32 | CC7.1, CC8.1 |
| 6. Observability | 8.15, 8.16, 8.17 | V7 | DE.AE, DE.CM | 5(1)(f), 33, 34 | CC7.2, CC7.3, CC7.4 |
| 7. Resilience | 5.29, 5.30, 8.6, 8.13, 8.14 | V11 | PR.IR-2..3, RC.RP | 32(1)(c) | A1.2, A1.3 |
| 8. Governance | 5.1, 5.2, 5.7, 5.19–5.30 | — | GV, RS | 5, 13–15, 17, 20, 25, 30, 32–35, 37 | CC1–CC5, CC9 |

---

## 7. Working agreements

- **One slice per branch**, branch name `fix/sec-AN-<short-slug>` or `feat/sec-BN-<short-slug>`.
- **One migration per slice** when DB is touched; never re-edit a landed migration — add a new numbered one.
- **No `--no-verify`, no `git push --force`, no `git reset --hard` on shared branches.**
- **Verification block** posted in PR description AND appended under the slice in this file.
- **Decisions Log** updated whenever scope, defaults, or sequencing deviates from this plan.
- **Surgical edits only** — no opportunistic refactors inside security slices.

---

## 8. Decisions Log

> Append-only. Newest entry on top.

- **2026-05-29 — Slice A5 hosted PASS + phase 3 (retention purge).** Migration 017 applied to hosted Supabase via dashboard; user triggered OTP verify + session create and confirmed both audit timelines populated. Phase 3 ships the nightly cleanup as a Netlify scheduled function rather than `pg_cron` (pg_cron not enabled in this project — verified zero matches across migrations). Schedule `17 3 * * *` chosen instead of `0 3 * * *` because every cron job on the planet runs at top-of-hour, so off-the-hour invocations land in a quieter window for both Netlify's scheduler and Supabase's query load. Deletion uses `.delete({ count: "exact" })` so the success log captures per-table row counts — small operational signal that proves the cleanup actually moved rows rather than silently no-op'ing forever. Function intentionally has no auth gate: it's idempotent (only touches already-expired rows) and the service-role key is sourced from env, so an attacker who can invoke it via POST gains nothing they couldn't already do with the env key directly.

- **2026-05 — Slice A5 phase 2 (audit log fan-out).** 12 wire-in points across 7 files: 5 auth surfaces (`requestOtpAction`, `signOutAndRedirectAction`, `getAdminSession` allowlist deny, `recover-request`, `recover-verify`) + 13 admin-action ops in 3 files (`quiz-bank-write` × 7, `admin-users/actions.ts` × 5, `onboarding/actions.ts` × 1). All wire-ins follow the same pattern: `void logAuthEvent(...)` / `void logAdminAction(...)` right after the operation's success / failure branch, before the response is built. The `void` prefix is load-bearing — it documents that the caller is not awaiting the audit insert, so a slow Supabase round-trip cannot extend the user's request latency. Subtleties: (a) `signOutAndRedirectAction` calls `supabase.auth.getUser()` *before* `signOut()` because once the cookies are cleared the user id is unrecoverable; (b) `getAdminSession` differentiates `lookup_error` (DB hiccup, deserves an alert) vs `not_on_allowlist` (legitimately rejected) vs `inactive` (was-an-admin, now isn't) via the `result` column so investigators can filter; (c) `recover-verify` writes the `userId` from the verified OTP (not from the recovered `app.users` row) so the audit row links to the authenticating Supabase identity even when the recovery row is for a different participant id; (d) `quiz-bank-write` factors the audit client + actor metadata above the switch so each case adds exactly 8 audit-related lines; (e) `inviteAdminAction`'s audit fires after the upsert succeeds, not after the Supabase invite email — invite-email failures are visible elsewhere and the admin_users row is the source of truth for \"this admin was created\".
- **2026-05 — Slice A5 phase 1 shape.** A5 split into three phases because 9 wire-in surfaces is too large a single diff. Phase 1 (this commit) ships the foundation: migration `017_audit_logging_tables.sql` (both tables + RLS + indexes + `expire_at` retention default of 730 days), single canonical `admin/src/lib/audit.ts` module (same shape as `rate-limit.ts` so Netlify functions can import it via `../../src/lib/audit`), a 7-test vitest suite, and smoke wire-ins on the two highest-signal paths — `verifyOtpAction` (success / fail / rate-limited branches) and `session-create` (the simplest admin write). Phase 2 will fan out to the remaining 7 surfaces; Phase 3 adds a scheduled retention purge. Deviations from the plan spec: (a) `pg_cron` is NOT enabled in this Supabase project (verified — zero matches across all migrations), so retention purge will be a scheduled Netlify function rather than a `cron.schedule`; (b) `session_refresh` dropped from the `event_type` check constraint — it's atomic per-request SSR cookie refresh inside middleware, logging every page navigation would explode the table without investigative value; (c) `otp_rate_limited` and `recover_rate_limited` added to the constraint — when a rate-limit kicks in we want it on the timeline distinct from a verify_fail; (d) IP/UA capture in Next.js server actions uses `headers()` from `next/headers` (works at runtime, returns null on error) rather than a separate route-handler wrapper. All `logAuthEvent` / `logAdminAction` calls are `void`-prefixed fire-and-forget; the module's try/catch guarantees audit failures never bubble into the request flow.
- **2026-05 — Slice A4 phase 2 (CSP enforcing).** Per user authorization, the CSP flip from `Content-Security-Policy-Report-Only` → `Content-Security-Policy` shipped immediately rather than after the 24h observation window. Three keys flipped in one commit (`netlify.toml`, `app/netlify.toml`, `admin/next.config.ts`); directives themselves unchanged from Phase 1. Risk accepted: any CSP directive miss now causes a hard block in the browser (white screen for the affected sub-resource or page) rather than a console warning. Recovery path if blocking violation surfaces: revert the three lines back to `-Report-Only` in a hotfix commit, observe the actual violation in DevTools, patch the directive, then re-flip. The 5 non-CSP headers (HSTS / XFO / nosniff / Referrer-Policy / Permissions-Policy) were already enforcing in Phase 1 and are unchanged here.
- **2026-05 — Slice A4 phase 1 shape.** Edge security headers ship in two phases. Phase 1 (initial commit): the 5 non-CSP headers (HSTS / XFO / nosniff / Referrer-Policy / Permissions-Policy) ship **enforcing**; CSP ships as **`Content-Security-Policy-Report-Only`** on both surfaces so violations surface in the DevTools console without blocking the page. Phase 2 (follow-up commit, after ~24h hosted observation): flip both header keys to `Content-Security-Policy` in `netlify.toml`, `app/netlify.toml`, and `admin/next.config.ts` (3 edits). Admin headers are duplicated across `netlify.toml` (edge) and `admin/next.config.ts` `async headers()` (framework) on purpose — defence-in-depth means either layer alone is enough to enforce, so an accidental delete on one side cannot silently un-secure. The two values are kept literally identical and the Phase 2 flip must touch both files in the same commit. Deviations from the plan baseline: `wss://*.supabase.co` added to admin `connect-src` (Supabase Realtime), `font-src 'self'` added (next/font/google self-hosts at build time, so no third-party font origin needed), `object-src 'none'` added (defence). For Flutter web: `'wasm-unsafe-eval'` added to `script-src` (CanvasKit + Skwasm WebAssembly), `https://challenges.cloudflare.com` added to `script-src` + `frame-src` + `child-src` + `connect-src` (Turnstile widget), `https://*.netlify.app` added to `connect-src` (functions origin; tighten to a single hostname when production functions hostname is locked), `worker-src 'self' blob:` + `child-src blob:` (Flutter service worker + CanvasKit blob workers), `font-src 'self' data:` (Flutter rasterizes embedded fonts via data URLs), `camera=(self)` in Permissions-Policy (mobile_scanner QR camera). No `report-uri` configured — DevTools console is the only observation channel in Phase 1; revisit if violation volume justifies a collector.
- **2026-05 — Slice A3 shape.** Three migrations shipped: `014_security_invoker_views.sql` flips both `app.ranked_attempt_totals_*` views to `security_invoker = true`; `015_admin_users_rls.sql` enables RLS on `app.admin_users` (the only `app.*` table that was missing it) with explicit `admin_users_service_role_all` (for) + `admin_users_self_select` (`auth.uid() = user_id`); `016_tighten_sessions_rls.sql` drops the permissive `sessions_public_select using (true)` policy and adds an explicit `sessions_service_role_all`. **Deviation from spec:** the plan called for a narrow anon `sessions_anon_join_lookup` policy gated on `status in ('open','live')`, but `app.sessions` has no `status` column — lifecycle is `starts_at`/`ends_at` only. An audit of every `app.sessions` caller (5 TS files in `admin/`, plus the Dart `session-resolve` path) showed every read goes through the service-role client, so deny-by-default for anon is correct; we did not speculatively add a permissive `[starts_at, ends_at)` window policy with no consumer. If a direct anon read use-case appears later, add the narrow policy then with a real client in mind. Service-role policies on `admin_users` and `sessions` are belt-and-suspenders — service_role bypasses RLS by default, but the explicit policies document intent and survive any future Supabase change to that bypass behaviour. Views are read only through `app.leaderboard_*` SQL functions called from `leaderboard.ts` with service-role, so `security_invoker = true` is a transparent change for current code while closing the Supabase advisor "Security Definer View" finding.
- **2026-05 — Slice A2 phase 3c shape.** Phase 3c is the final cleanup pass after Phase 3b shipped clean for one pilot session (user-confirmed 2026-05-28). `/device-token` now requires `turnstileToken` (missing → 400 `BAD_REQUEST`); the gate-key Path B branch is gone and `_shared/gate.ts` is deleted. CORS `access-control-allow-headers` lists in `_shared/http.ts` and `health.ts` no longer advertise `x-medrash-gate-key`. Flutter `AppConfig.gateApiKey`, `DeviceTokenStore._gateApiKey`, `MedRashHttpClient._gateApiKey` and the `x-medrash-gate-key` header attachment are all removed; `init_core.dart` no longer wires the value. `app/scripts/build-web.sh` now hard-requires `MEDRASH_TURNSTILE_SITE_KEY` and no longer requires `MEDRASH_GATE_API_KEY`. The `MEDRASH_GATE_API_KEY` Netlify env entry should be deleted after this deploy lands — it is no longer read anywhere in the codebase. `participant-auth.test.ts` was simplified: it no longer seeds `MEDRASH_GATE_API_KEY`, but the "stale gate-key header still 401s" case stays as a regression check (the header should be treated as ignorable noise).
- **2026-05 — Slice A2 phase 3b shape.** `/device-token` is **dual-path** in 3b (accepts either `turnstileToken` body field OR `x-medrash-gate-key` header) for exactly the same reason 3a was code-only: shipping Turnstile-required AND deleting the gate-key fallback in one commit would brick every live build for one deploy cycle. The Turnstile path is preferred when present; a present-but-invalid Turnstile token returns 401 immediately rather than silently falling back to the gate key — same strict ordering choice as 3a `participant-auth`. Flutter web Turnstile integration uses a vanilla-JS shim in `index.html` (`window.medrashTurnstileExecute(siteKey)`) called from Dart via `dart:js_interop`, with conditional imports for non-web platforms (stub returns null). The JS shim owns the widget lifecycle (lazy script load, hidden invisible host div, hard 12s timeout) so the Dart side never needs to manage Cloudflare state. Site key arrives via `--dart-define=MEDRASH_TURNSTILE_SITE_KEY=…` (public, not a secret — bound to a domain in the Cloudflare dashboard). Rate-limit module is in-memory + per-function-instance; this is best-effort defense (warm instance is sticky enough for a single attacker) but a real distributed-DDoS posture would need Upstash/Redis — deferred until traffic justifies the dependency.
- **2026-05 — Slice A2 phase 3a split.** Phase 3 itself bisected into 3a (this commit, code-only deletion of the already-disabled fallback branch) and 3b (next commit, Turnstile + rate-limit on `/device-token`, delete `_shared/gate.ts`, drop `_gateApiKey` from Flutter). The split exists because requiring Turnstile on `/device-token` and removing the gate-key fallback in the same commit would brick every live build that hasn't shipped a Turnstile widget yet — mint would fail, no bearer would be sent, no fallback would catch it, every request 401s. 3a is a no-op runtime change in prod (the fallback branch was already dead with `MEDRASH_GATE_KEY_FALLBACK=false` confirmed by user), so it's safe to ship before the Flutter widget is in place. Bootstrap protection chosen as Cloudflare Turnstile (invisible) + per-IP+device in-memory rate limit, per user direction. Turnstile is web-first and matches the pilot's web-only target; mobile attestation parked for a later pillar.
- **2026-05 — Slice A2 phase 2 shape.** `DeviceTokenStore` is a separate object from `MedRashHttpClient` (injected via an optional `tokenProvider: Future<String?> Function()` callback) instead of an internal field on the HTTP client, because the store needs to call `/device-token` to mint — if the store *was* the HTTP client, mint would recurse through the bearer path. Keeping the store standalone with its own `http.Client` cleanly avoids the loop and keeps the HTTP client a pure transport. During Phase 2 both headers (`Authorization: Bearer …` and `x-medrash-gate-key …`) ship on every request — bearer is preferred server-side, gate key is the fallback if the token store has not yet minted (cold start, mint failure). The store falls back to a cached-but-past-refresh token if a fresh mint fails and the cache is still pre-expiry, so a brief network blip never logs a participant out. Concurrent `currentToken()` callers single-flight into one mint via a `Future<String?>? _inflight` field, so the burst of repository calls at app startup does not stampede `/device-token`.
- **2026-05 — Slice A2 phase 1 shape.** Token wire format chosen as `${base64url(payloadJsonString)}.${base64url(sig)}` instead of the spec's `${did}.${pid}.${iat}.${nonce}` string. Same HMAC inputs (sig = HMAC-SHA256(secret, payloadB64)), but a structured JSON payload lets `verifyDeviceToken()` return parsed claims directly without a second parser. `MEDRASH_GATE_KEY_FALLBACK` defaults to **enabled** (opt-out via `false`/`0`/`off`/`no`), inverting the spec's "flagged by env" wording — required because Phase 1 ships the backend before Flutter is updated, so a missing env var must not lock live participants out. Bearer-then-fallback ordering is strict: a present-but-invalid bearer returns 401 immediately rather than silently retrying the legacy gate key, so client bugs surface instead of being masked by a stale shared secret. A2 split into three phases (backend dual-path → Flutter switchover → kill-switch) so the rollout cannot brick existing builds.
- **2025-01 — Slice A1 shape.** Single shared module lives at `admin/src/lib/rate-limit.ts` (not `admin/netlify/functions/_shared/`) because Netlify functions in this repo already import from `../../src/lib/` (e.g. `session-create.ts`, `quiz-bank-write.ts`) and the Next.js server action at `admin/src/app/login/actions.ts` cannot reach a path under `netlify/functions/`. Identifiers are SHA-256 hashed before storage so `app.auth_rate_limit` never holds raw emails or IPs — pre-pays Slice A5's privacy discipline. Atomicity is enforced inside a plpgsql function (`enforce_rate_limit`) using `select … for update`, so concurrent verifies on the same key serialize cleanly. Lockout equals window (15 min) so a tripped limit resolves on the next window roll-over without a separate decay job.

---

## 9. Out of scope (this plan)

- Organisational IT hygiene (laptop disk encryption, MDM, employee onboarding/offboarding).
- Payroll / financial security.
- Physical security of any office or data centre (covered by Supabase + Netlify's own certifications).
- Mobile app store account security (Apple Developer / Google Play org).
- Marketing site security (handled separately if/when it exists).

---

## 10. Definition of Done — for each slice

A slice is Done when **all** of:

1. Code committed to a feature branch with surgical scope.
2. Verification block populated with PASS evidence for every required check.
3. PR opened with verification block in the description.
4. Reviewer (or self-review with a written justification) signs off.
5. Merged to `main`, deployed to hosted Supabase + Netlify.
6. Post-deploy smoke check executed against hosted environment, PASS noted in this file.
7. Checkbox flipped from `[~]` to `[x]` in this file in the same PR or an immediate follow-up.

---

_End of plan. Next action: kick off **Slice A1 — Persist OTP + per-IP rate limit in Postgres**._
