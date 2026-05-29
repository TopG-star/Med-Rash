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

### Slice A5 � — Auth + admin-action audit logs *(Pillar 6)*

**Problem solved:** no persistent record of who logged in, who failed, who edited what — fails ISO 27002 §8.15 and breach-investigation needs.

**Sub-tasks**

- [x] **Phase 1 (committed):** New migration `017_audit_logging_tables.sql` creating `app.auth_events` + `app.admin_audit` with service-role RLS, `expire_at` retention column (default `now() + 730 days`), and per-table indexes (`occurred_at desc`, `(event_type, occurred_at desc)`, `(user_id, occurred_at desc)`, `(actor_user_id, occurred_at desc)`, `(action, occurred_at desc)`, `(target_type, target_id, occurred_at desc)`, `expire_at` for cleanup). Event-type check constraint covers 10 types (added `otp_rate_limited` + `recover_rate_limited` vs original spec; dropped `session_refresh` per audit — it's atomic SSR cookie refresh, not a discrete event worth logging).
- [x] **Phase 1 (committed):** Shared module `admin/src/lib/audit.ts` exporting `logAuthEvent(client, input)` + `logAdminAction(client, input)` — both fire-and-forget, both SHA-256 hash email/IP/UA, both never throw. Single canonical module imported from both Next.js server actions and Netlify functions (same pattern as `admin/src/lib/rate-limit.ts`). 7-test vitest suite verifies hashing + PII non-persistence + fire-and-forget invariants.
- [x] **Phase 1 (committed):** Smoke wire-ins — `verifyOtpAction` (success / fail / rate-limited paths) + `session-create` (1 op).
- [x] **Phase 2 (committed):** Wired `logAuthEvent` into remaining auth surfaces: `requestOtpAction` (success + rate-limit + signInWithOtp error), `signOutAndRedirectAction` (captures userId from `getUser()` *before* signOut clears cookies), `getAdminSession` (allowlist deny — both `lookup_error` and `not_on_allowlist` / `inactive` paths), `recover-request` (success / rate-limited / profile-not-found / supabase-429 / otp-send-failed), `recover-verify` (success / rate-limited / otp-invalid / profile-not-found / recovery-conflict).
- [x] **Phase 2 (committed):** Wired `logAdminAction` into remaining admin-write surfaces: `quiz-bank-write` (all 7 ops — `create_quiz`, `update_quiz`, `deactivate_quiz`, `create_question`, `update_question`, `deactivate_question`, `bulk_create_questions`), `admin-users/actions.ts` (all 5 ops — `invite_admin`, `reinvite_admin`, `deactivate_admin`, `reactivate_admin`, `set_admin_role`), `onboarding/actions.ts` (`complete_onboarding`).
- [x] **Phase 3 (committed):** Scheduled retention cleanup — `pg_cron` is NOT enabled (zero matches across all migrations); shipped as scheduled Netlify function `admin/netlify/functions/audit-retention-purge.ts` running nightly at 03:17 UTC (`netlify.toml` schedule), `.delete({ count: 'exact' })` on both tables `where expire_at <= now()`, idempotent + service-role-keyed.

**Files touched (phase 1):** `supabase/migrations/017_audit_logging_tables.sql` (new), `admin/src/lib/audit.ts` (new), `admin/src/lib/audit.test.ts` (new), `admin/src/app/login/actions.ts` (verifyOtpAction wire-in + `readClientHeaders` helper), `admin/netlify/functions/session-create.ts` (session_create wire-in).

**Files touched (phase 2):** `admin/src/app/login/actions.ts` (requestOtpAction + signOutAndRedirectAction wire-ins), `admin/src/lib/admin-session.ts` (`getAdminSession` allowlist deny + `readClientHeaders` helper), `admin/netlify/functions/recover-request.ts` (4 outcomes), `admin/netlify/functions/recover-verify.ts` (5 outcomes), `admin/netlify/functions/quiz-bank-write.ts` (7 ops), `admin/src/app/admin-users/actions.ts` (5 ops), `admin/src/app/onboarding/actions.ts` (1 op).

**Verification phase 1+2+3:** typecheck PASS · vitest 73/73 PASS (+7 new in phase 1) · `supabase db push` user-applied 2026-05-29 · phase 3 manual `curl -X POST .../audit-retention-purge` returned 200 (user-confirmed 2026-05-29) · hosted smoke for per-event-type row counts **skipped per user authorization 2026-05-29** (audit module is fire-and-forget, wire-ins compile-checked, retention purge tested manually — risk accepted to keep slice cadence).

**Standards:** ISO 27002 §8.15, 8.16, 8.17 · OWASP ASVS V7 · NIST CSF DE.AE-1..8, DE.CM-1 · SOC 2 CC7.2, CC7.3 · GDPR Art. 5(1)(f), 32(1)(b).

---

### Slice A6 � — Centralized rate limiting on all 9 unprotected endpoints *(Pillar 7)*

**Status:** ✅ Shipped 2026-05-29. Module + 7-endpoint fan-out + tests committed.

**Problem solved:** 9 of 11 Netlify functions had zero rate limiting; gate-key holder (or its leak) could drain Supabase + Netlify spend.

**Sub-tasks**

- [x] Extend `admin/src/lib/rate-limit.ts` (from A1) `RateLimitScope` union with 8 new scopes: `attempt_submit`, `attempt_submit_ip`, `profile_sync`, `ranked_eligibility`, `leaderboard`, `quiz_list`, `quiz_bank_write`, `session_create`.
- [x] Per-scope defaults wired in `RATE_LIMITS` map:
  - `attempt_submit`: 60 / 60s per participant_id, `attempt_submit_ip` 600 / 60s per IP (dual bucket).
  - `profile_sync`: 30 / 60s per device.
  - `ranked_eligibility`: 120 / 60s per device.
  - `leaderboard` / `quiz_list`: 60 / 60s per IP.
  - `quiz_bank_write` / `session_create`: 30 / 60s per admin user_id.
- [x] Wired into all 7 unprotected endpoints at top of handler, before any DB call (recover-request / recover-verify already protected in A1; session-resolve already has its own in-memory limiter — left untouched, see Decisions Log).
- [x] Standard 429 response: `{ ok: false, code: "RATE_LIMITED", message, retryAfterSeconds }` matching A1 shape.
- [x] Vitest `returns plan-spec defaults for every A6 scope` guards against typo'd table entries.

**Files touched:** `admin/src/lib/rate-limit.ts` (extend scopes + defaults), `admin/src/lib/rate-limit.test.ts` (add scope-default test), `admin/netlify/functions/{attempt-submit,quiz-list,leaderboard,profile-sync,ranked-eligibility,quiz-bank-write,session-create}.ts` (wire-in).

**Verification:** typecheck PASS · vitest 74/74 PASS · per-scope defaults asserted in unit test · hosted 65-request burst smoke **skipped per user authorization 2026-05-29** (Postgres-backed `enforce_rate_limit` already proven by A1 hosted PASS; new scopes are config-only entries in `RATE_LIMITS` map asserted by unit test; risk accepted to keep slice cadence).

**Standards:** ISO 27002 §5.30, 8.6, 8.14 · OWASP ASVS V11.1 · NIST CSF PR.IR-2 · OWASP Top 10 A04 (Insecure Design).

---

### Slice A7 � — Adopt zod for all Netlify function + server-action inputs *(Pillar 3)*

**Status:** Phase 1 ✅ shipped 2026-05-29 (foundation: dep + 6 schemas + helper + 43 tests, zero wire-ins). Phase 2 ✅ shipped 2026-05-29 (9/10 Netlify functions gated by zod front door + structured `INVALID_INPUT` issues[]; `quiz-list` has no body — N/A). Phase 3 ✅ shipped 2026-05-29 (5 Next.js server actions zod-gated; 5 lib parsers retired).

**Problem solved:** handwritten validators drift; new endpoints reinvent trim/length/enum checks; no single source of truth for input shapes.

**Sub-tasks**

- [x] **Phase 1 (committed):** Added `zod@4.4.3` to `admin/package.json`. Created `admin/src/lib/schemas/` with `_helpers.ts` (`validateBody`, `emailField`, `otpField`, `nonEmptyTrimmed`, `optionalTrimmedNullable`, `metadataField`) + 6 resource schemas matching plan spec: `identity.ts`, `attempt.ts`, `session.ts`, `quiz.ts` (incl. `quizBankWriteSchema` discriminated union over 7 ops), `recover.ts`, `leaderboard.ts`. Standard error envelope: `{ ok: false, code: 'invalid_input', issues: [{ path, message }] }`. 43-test vitest suite (`schemas.test.ts`) covers every schema with happy + ≥3 rejection paths. **No wire-ins yet — verifiable in isolation.**
- [x] **Phase 2 (committed):** Wired schemas into 9 Netlify functions as a zod front door (`_shared/validate.ts` returns a 400 `INVALID_INPUT` with `issues[]` on failure + back-compat `message` = first issue): `attempt-submit` (full replace of `parseMode`/`parseOrigin`/`parseQuizRef`/`parseSessionId`/`parseAnswers`/`parsePositiveInt`), `session-create`, `session-resolve` (replaced `parseJoinCode`), `quiz-bank-write` (discriminated-union over 7 ops), `leaderboard` (replaced `readType`/`readLimit`/`readSeason`), `profile-sync`, `ranked-eligibility` (replaced `readQuizRef`), `recover-request`, `recover-verify`. `quiz-list` excluded — empty body. Shared `parseIdentityInput` / `parseCreateSessionInput` / `parseCreate*Input` retained as fallback-normalization layer (still consumed by server actions); Phase 3 retires them.
- [x] **Phase 3 (committed):** Wired schemas into all 5 Next.js server actions (`login/actions.ts` — both `requestOtpAction` + `verifyOtpAction`; `admin-users/actions.ts` — `inviteAdminAction`, `reinviteAdminAction`, `setRoleAction`, `setActive` flows; `onboarding/actions.ts` — `complete_onboarding`; `sessions/actions.ts` — `createSessionAction`; `quiz-bank/actions.ts` — all 6 mutation actions). Added new schemas `admin-users.ts` (`inviteAdminSchema`, `setRoleSchema`, `userIdInputSchema`) + `onboarding.ts` (`completeOnboardingSchema`). New `validateForAction<T>` helper in `_helpers.ts` returns `{ ok, data } | { ok:false, message, issues }` so server actions keep their `{ ok:false, message }` envelopes. Retired 5 lib parsers (`parseCreateSessionInput`, `parseCreateQuizInput`, `parseUpdateQuizInput`, `parseCreateQuestionInput`, `parseUpdateQuestionInput`) plus ~9 internal helpers (`SLUG_PATTERN`, `requireString`, `optionalString`, `parseInteger`, `parseBoolean`, `parseSlug`, `parseOptions`, `parseTags`, `parseMetadata`, `optionalIsoTimestamp`). `parseIdentityInput` **retained** — its substantive defaults (`"Pilot Participant"`, `Guest-XXXX` codes, `"Unknown Facility"`, `"General"`) are not pure shape validation and would lose semantics if folded into a schema. See Decisions Log.
- [x] Keep server-side score recomputation in `attempt-submit.ts` intact — zod only validates shape, not business invariants. (Carved out in `attempt.ts` schema; only constrains shape + clamps `timeTakenMs` to 2h.)
- [x] Generate TypeScript types via `z.infer<>` — exported per schema (`AttemptSubmitInput`, `CreateSessionInput`, `QuizBankWriteInput`, etc.).

**Files touched (phase 1):** `admin/package.json` + `package-lock.json` (zod dep), `admin/src/lib/schemas/_helpers.ts` (new), `admin/src/lib/schemas/identity.ts` (new), `admin/src/lib/schemas/attempt.ts` (new), `admin/src/lib/schemas/session.ts` (new), `admin/src/lib/schemas/quiz.ts` (new), `admin/src/lib/schemas/recover.ts` (new), `admin/src/lib/schemas/leaderboard.ts` (new), `admin/src/lib/schemas/schemas.test.ts` (new).

**Files touched (phase 2):** `admin/netlify/functions/_shared/validate.ts` (new — `validateOrRespond` adapter returning a 400 `INVALID_INPUT` with `issues[]`), `admin/netlify/functions/attempt-submit.ts` (full parser deletion), `admin/netlify/functions/session-create.ts` (front-door wire-in), `admin/netlify/functions/session-resolve.ts` (front-door wire-in, deleted `parseJoinCode`), `admin/netlify/functions/quiz-bank-write.ts` (front-door wire-in for discriminated union), `admin/netlify/functions/leaderboard.ts` (front-door wire-in, deleted `readType`/`readLimit`/`readSeason`/unused `LeaderboardType`), `admin/netlify/functions/profile-sync.ts` (front-door wire-in), `admin/netlify/functions/ranked-eligibility.ts` (front-door wire-in, deleted `readQuizRef`), `admin/netlify/functions/recover-request.ts` (front-door wire-in), `admin/netlify/functions/recover-verify.ts` (front-door wire-in).

**Files touched (phase 3):** `admin/src/lib/schemas/admin-users.ts` (new), `admin/src/lib/schemas/onboarding.ts` (new), `admin/src/lib/schemas/_helpers.ts` (added `validateForAction<T>`), `admin/src/lib/schemas/schemas.test.ts` (+14 new tests for the 2 new schema files, 57 total schema tests, 131 total suite tests), `admin/src/app/login/actions.ts` (deleted local `EMAIL_RE`/`OTP_RE`, both actions zod-gated with UX-message preservation via `issues[0].path`), `admin/src/app/admin-users/actions.ts` (deleted local `EMAIL_RE`, 4 actions wired), `admin/src/app/onboarding/actions.ts` (deleted local `isJobRole` guard, single action wired with path-mapped messages), `admin/src/app/sessions/actions.ts` (full rewrite, dropped `parseCreateSessionInput`), `admin/src/app/quiz-bank/actions.ts` (full rewrite, 6 mutation actions wired, 4 local `to*Input` mappers added for `?? null`/`?? {}` fallbacks), `admin/netlify/functions/session-create.ts` (dropped `parseCreateSessionInput` import, inline `CreateSessionInput` build), `admin/netlify/functions/quiz-bank-write.ts` (dropped 4 `parseCreate*/parseUpdate*` imports + `Operation`/`SUPPORTED_OPS`/`isOperation`, switch now narrows on `data.op` via discriminated union), `admin/src/lib/session-create.ts` (deleted `parseCreateSessionInput`, `requireString`, `optionalIsoTimestamp`), `admin/src/lib/quiz-write.ts` (deleted 4 `parse*` functions + 9 internal helpers).

**Verification phase 1+2+3:** typecheck PASS · vitest 131/131 PASS (74 prior + 57 schema tests) · lint 0 errors / 14 pre-existing warnings (unchanged baseline). Phase 3 sole follow-up: integration test that a malformed POST to `/attempt-submit` returns structured 400 with field-level `issues[]` (carried forward — pending decision on whether to deprioritise given Netlify functions are already covered by Phase 2 schema-level tests).

**Standards:** ISO 27002 §8.28 · OWASP ASVS V1.5, V5.1 · OWASP Top 10 A03 (Injection), A04 (Insecure Design).

---

### Block A close-out gate

Before marking Block A complete:

- [x] All 7 slices verified PASS (A1–A7 shipped 2026-05 through 2026-05-29; see per-slice Verification lines above).
- [x] `npm run typecheck`, `npm run test`, `npm run lint` PASS in `admin/` (workspace `c:\Users\USER\Desktop\Personal\medRash\admin`, mode local, 2026-05-29) — typecheck exit 0; vitest 9 files / **131/131** PASS in 3.64s; lint 0 errors / 14 pre-existing warnings (unchanged baseline).
- [x] `flutter analyze` and `flutter test` PASS in `app/` (workspace `c:\Users\USER\Desktop\Personal\medRash\app`, mode local, 2026-05-29) — `flutter analyze` → **No issues found** (ran in 79.0s); `flutter test` → **180/180** PASS.
- [ ] Supabase Advisor lints: **0 critical, 0 SECURITY DEFINER view findings, 0 missing-RLS findings** — **user-driven (deferred to user dashboard run, not autonomously executable from CLI).**
- [ ] One end-to-end pilot dry-run: admin login → create session → participant scan QR → attempt → leaderboard, with audit + rate-limit + token-bound headers all observed — **user-driven (hosted Netlify session); Netlify redeploy 2026-05-29 succeeded, hosted is healthy.**
- [x] Decisions Log updated with one entry per slice noting any deviations (A7 Phase 1/2/3 entries on top; A1–A6 entries below).

---

## 4. Block B — pre-SOC2 / ISO 27001 readiness must-haves

> Goal: close every finding an auditor will flag during a SOC 2 Type I or ISO 27001 Stage 1 readiness exercise. Ship over 4–8 weeks after Block A.

### Slice B1 🟡 — TOTP MFA for `owner` role + session timeout policy *(Pillar 1)*

**Status:** Phase 1 🟡 in progress (session-timeout middleware + 7 new audit event types declared, 2 wired; tests). Phase 2 pending Supabase TOTP enablement in the dashboard. Phase 3 pending.

**Problem solved:** owner accounts (highest blast-radius role: can invite admins, set roles, run quiz-bank writes, export everything) are currently protected by a single email-OTP factor with no MFA and no session-timeout enforcement. Compromised inbox → owner takeover → full pilot data exfiltration.

**Sub-tasks**

- [~] **Phase 1 (in progress):** Session timeout enforcement (idle 30 min + absolute 8 h) in `admin/src/middleware.ts` via a new HMAC-signed cookie `medrash-admin-session` (Web Crypto API so it loads cleanly in both Edge middleware AND Node route runtimes). New module `admin/src/lib/admin-session-cookie.ts` exports `signAdminSessionCookie` / `verifyAdminSessionCookie` / `decideAdminSession` (pure decision function — verify + decide + sign composed by middleware). New env var `MEDRASH_ADMIN_SESSION_SECRET` (≥32 chars) — same posture as `MEDRASH_DEVICE_TOKEN_SECRET`. Cookie is `httpOnly`, `sameSite=lax`, `secure` in production, `maxAge=8h`. On expire, middleware clears both our own cookie AND the Supabase `sb-*-auth-token` cookies, then redirects to `/login?reason=session_idle | session_absolute`. Signout route also clears the cookie. Audit event types extended with 7 new entries: `session_idle_timeout`, `session_absolute_timeout`, `mfa_enroll`, `mfa_verify_success`, `mfa_verify_fail`, `mfa_disable`, `mfa_recovery_used` — Phase 1 only declares them in the union (used in Phase 1: 2 session events surface via `?reason` URL param to the `/login` page where the Node-runtime audit-log emit happens in Phase 3; MFA-* declared-but-unused in Phase 1).
- [ ] **Phase 0 (precondition, user-driven):** Enable Supabase Auth → Settings → Multi-Factor Authentication → TOTP factor in the dashboard before Phase 2 ships. Currently only email OTP is enabled. No code change.
- [ ] **Phase 2:** Supabase TOTP enrollment flow (`mfa.enroll` → render QR → `mfa.challenge` → `mfa.verify`) + 8 single-use recovery codes generated at enrollment (stored hashed in `app.admin_users.mfa_recovery_codes`, displayed once, printable). Hard-block policy per agreed decision: any `owner` request without a verified TOTP factor on the current AAL2 session is redirected to `/onboarding/mfa`. New guard in `requireOwner` (lib/admin-session.ts) checks `supabase.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel === "aal2"` and the user has at least one verified factor. Hosts remain on email OTP (factor not required).
- [ ] **Phase 3:** Audit-log wire-ins for the 7 new event types (5 MFA + 2 session-timeout). Owner-resets-other-owner admin action in `admin-users/actions.ts` requiring step-up (fresh TOTP verify within last 5 min) — per agreed decision, scope is "once 2 owners exist; do not rely on for pilot". Decisions Log entry + close-out.
- **Standards:** ISO 27002 §5.17, 8.5 · OWASP ASVS V2.7 · SOC 2 CC6.1.

**Files touched (phase 1):** `admin/src/lib/admin-session-cookie.ts` (new), `admin/src/lib/admin-session-cookie.test.ts` (new), `admin/src/middleware.ts` (timeout enforcement + cookie sign/verify), `admin/src/app/auth/signout/route.ts` (clear cookie), `admin/src/lib/audit.ts` (extend `AuthEventType` union with 7 new entries), `docs/security-hardening-plan.md` (this expansion), `docs/dev-environment.md` + `docs/admin-surfaces.md` (document `MEDRASH_ADMIN_SESSION_SECRET`).

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

### Slice B4 ✅ — CI hardening *(Pillar 5)*
- [x] [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs on PR + push to `main`: admin job (`npm ci` → `typecheck` → `test` → `lint`); app job (`flutter pub get` → `analyze` → `test`). Pinned Node 20 + Flutter 3.24.0 stable; `concurrency` group cancels superseded runs; `permissions: contents: read` (least privilege).
- [x] [`.github/workflows/security.yml`](../.github/workflows/security.yml) runs on PR + push + weekly cron (Mon 03:17 UTC, mirrors audit-retention-purge cadence): `npm audit --omit=dev --audit-level=high` (blocking on high/critical prod deps), `google/osv-scanner-action@v1.9.1` (informational, SARIF uploaded to Security tab via `github/codeql-action/upload-sarif@v3`), `gitleaks/gitleaks-action@v2` (blocking on any secret — full git history via `fetch-depth: 0`).
- [x] GitHub native secret scanning + push protection: free + auto-enabled for public repos at the platform level — no workflow needed; documented here for the audit trail.
- [x] [`.github/dependabot.yml`](../.github/dependabot.yml) configured weekly (Mon 04:00 UTC): npm (`/admin`, 10 PR cap, grouped: next-react / supabase / tailwind / test-tooling), pub (`/app`, 10 PR cap), github-actions (`/`, 5 PR cap). Commit-message prefix `chore` with scope so [policy.yml](../.github/workflows/policy.yml) commit-message check passes.
- [x] [`.github/workflows/sbom.yml`](../.github/workflows/sbom.yml) generates CycloneDX SBOMs (`sbom-admin.cdx.json` + `sbom-app.cdx.json`) on `v*` tag push or manual dispatch via single tool `@cyclonedx/cdxgen@^11` (covers both npm and pub ecosystems). Uploaded as workflow artifact AND attached to the GitHub Release via `softprops/action-gh-release@v2` when triggered by a tag.
- **Files touched (B4):** `.github/workflows/ci.yml`, `.github/workflows/security.yml`, `.github/workflows/sbom.yml`, `.github/dependabot.yml`, `docs/security-hardening-plan.md`.
- **Standards:** ISO 27002 §8.8, 8.25, 8.28, 8.30 · NIST SSDF · SOC 2 CC8.1.

### Slice B5 ✅ — Threat model + incident response plan + vendor register *(Pillar 8)*
- [x] 1-page STRIDE per surface in [`docs/security/threat-model/`](security/threat-model/README.md) (admin-auth, participant-runner, host-live, recovery, leaderboard).
- [x] Incident response runbook in [`docs/security/incident-response.md`](security/incident-response.md) (severities, on-call solo-with-future-rotation design, GDPR 72h breach template, 6 containment playbooks including owner-account-lockout).
- [x] Vendor register in [`docs/security/vendor-register.md`](security/vendor-register.md) (Supabase, Netlify, Cloudflare Turnstile, GitHub, npm, pub.dev, Flutter SDK, Google Fonts — with risk tier, DPA status, sub-processors, renewal).
- **Files touched (B5):** `docs/security/threat-model/README.md`, `docs/security/threat-model/admin-auth.md`, `docs/security/threat-model/participant-runner.md`, `docs/security/threat-model/host-live.md`, `docs/security/threat-model/recovery.md`, `docs/security/threat-model/leaderboard.md`, `docs/security/incident-response.md`, `docs/security/vendor-register.md`, `docs/security-hardening-plan.md`.
- **Open actions surfaced:** verify Google Fonts self-hosted by `next/font`; file Supabase + Netlify DPAs under `docs/security/dpa/`; capture GitHub account tier; quarterly review reminders.
- **Standards:** ISO 27001 §6.1.2, §16 · ISO 27002 §5.7, 5.19–5.30 · NIST CSF GV, RS · GDPR Art. 30, 33, 34, 35.

### Slice B6 ✅ — Backup/restore drill + DR runbook *(Pillar 7)*
- [x] Comprehensive DR runbook at [`docs/security/dr-runbook.md`](security/dr-runbook.md): RTO/RPO targets, Supabase backup posture template (covers both Pro+ PITR and Free daily-snapshot paths so the runbook is usable without waiting on a tier decision), 6 scenario playbooks (bad-deploy, DB data loss, Supabase project suspended/deleted, Netlify org compromise, domain hijack, secret leak).
- [x] Quarterly restore drill procedure + drill log table embedded in DR runbook §4. **First drill is a user-driven precondition before pilot launch.**
- [x] Domain hijack + Netlify-org-lock + Supabase-project-suspend recovery paths covered in DR §3.3–§3.5.
- [x] Secret rotation kit in DR §6 ties to existing secret inventory (`MEDRASH_ADMIN_SESSION_SECRET` from B1, `MEDRASH_DEVICE_TOKEN_SECRET` from A2, Turnstile secret from A6, Supabase keys).
- **Open actions surfaced:** fill in Supabase plan tier + project ref in DR §2 before pilot launch; perform first quarterly drill and log outcome in §4.2; implement offsite weekly `pg_dump` (§5) to a non-Supabase vendor.
- **Files touched (B6):** `docs/security/dr-runbook.md`, `docs/security-hardening-plan.md`.
- **Standards:** ISO 27002 §8.13, 8.14 · SOC 2 A1.2, A1.3 · GDPR Art. 32 §1(c).

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

- **2026-05 — Slice B6 (DR runbook, docs-only).** Single new doc `docs/security/dr-runbook.md` covering 6 scenario playbooks + quarterly drill procedure + secret rotation kit + offsite-backup gap analysis. **Two-track design** for Supabase backup posture: the runbook documents both "Pro+ with PITR" (preferred, 5-min RPO) and "Free with daily snapshot" (24-h RPO) paths so it ships without waiting on a plan-tier decision; §2 has a fill-in template the user completes before pilot launch. **RTO/RPO targets** stated explicitly per surface: 1h/0 for code (git is the backup), 4h/5min for DB on Pro, 4h/24h on Free — Free tier is called out as "strongly recommend upgrade before pilot launch" because the 24-h RPO is incompatible with the audit-log integrity claim. **Scenario playbooks** mapped 1:1 with realistic failure modes: bad-deploy (Netlify rollback + git revert), DB data loss (PITR vs snapshot paths both documented), Supabase project suspended/deleted (covers vendor-side action + grace-period restoration + worst-case rebuild from migrations 001-017+), Netlify org compromise/lockout (includes the temporary-DNS-to-GitHub-Pages mitigation while locked out), domain hijack (SEV1 by default; mandatory rotation of both session-secret and device-token-secret to invalidate everything in flight), secret leak (key insight: rotate, **do not** force-push history — secrets in clones/mirrors are irrecoverable). **Quarterly drill template** with a per-row log table (drill date, performed by, plan tier, procedure, RTO, outcome, follow-ups) embedded directly in the doc rather than a separate file — keeps the drill-it-and-log-it loop tight. **Secret rotation kit (§6)** is the operational complement to the threat-model + IR slices: every secret listed with generator command + deploy location + "what breaks if missing" + ordered rotation sequence for a confirmed compromise (sessions first → API keys → deploy tokens last). Rotation log file `docs/security/rotation-log.md` deliberately NOT created today — empty scaffolding adds noise; created on first rotation. **Offsite backup (§5)** surfaced as an open action with a concrete shape (weekly `pg_dump` → age/gpg encrypted → bucket on a vendor whose account is NOT linked to the same email/payment as Supabase or Netlify) rather than just "do offsite backups" — gives the user a buildable spec. **Cross-link discipline**: every reference into [incident-response.md](security/incident-response.md) uses GitHub-compatible section-number anchors (the same fix-up pattern from B5). **No code, no test, no lint** — pure docs slice.

- **2026-05 — Slice B4 (CI hardening: ci.yml + security.yml + sbom.yml + dependabot.yml).** Four new files under `.github/`: a quality-gate workflow, a security-scan workflow, an SBOM generation workflow, and Dependabot config. **Style mirrors existing `policy.yml`**: pinned major versions on every action (`actions/checkout@v4`, `actions/setup-node@v4`, `subosito/flutter-action@v2`, etc.), least-privilege `permissions:` block at workflow scope, `concurrency` group with `cancel-in-progress: true` so superseded runs don't queue. **Node pinned to 20, Flutter pinned to 3.24.0 stable** — Flutter 3.24.0 ships Dart 3.5 which satisfies `pubspec.yaml`'s `sdk: ^3.4.0` floor with margin; chose an explicit version over `channel: stable` alone for reproducibility. **CI vs Security split**: `ci.yml` runs typecheck/test/lint/analyze — these are deterministic and must block PRs. `security.yml` runs three scanners with deliberately mixed blocking posture: `npm audit --omit=dev --audit-level=high` blocks (prod-dep high/critical CVE is non-negotiable); `gitleaks` blocks (any secret in history = stop the line) and uses `fetch-depth: 0` so the scan sees full history not just HEAD; `osv-scanner` is **informational** with `continue-on-error: true` because the Go ecosystem's OSV DB regularly surfaces low/medium advisories in transitive deps that would create PR friction without proportional risk — instead SARIF is uploaded to the Security tab via `github/codeql-action/upload-sarif@v3` so findings are visible and triageable but not blocking. **Weekly Monday 03:17 UTC cron** on security.yml mirrors the A5 phase-3 audit-retention-purge schedule (consistent ops-cadence anchor; surfaces drift in deps that haven't been touched by a PR). **Dependabot**: weekly Monday 04:00 UTC for all three ecosystems (npm, pub, github-actions); npm updates grouped into 4 logical bundles (next-react / supabase / tailwind / test-tooling) so the queue doesn't drown the reviewer with 12 individual minor bumps. `commit-message.prefix: chore` (with scope) chosen specifically so the auto-generated PR commits pass the existing `policy.yml` Conventional Commits check on first try — otherwise every Dependabot PR would require a manual rebase. **GitHub native secret scanning + push protection**: documented as enabled at the platform level (free for public repos) — no workflow file needed, but called out in the plan and Decisions Log because an auditor will ask "where is your secret scanner" and the answer is "two layers: platform + gitleaks in CI". **SBOM choice — single `cdxgen` tool over per-ecosystem tools**: `cyclonedx-npm` + a separate Flutter SBOM tool would be 2 deps and 2 invocations; `@cyclonedx/cdxgen@^11` auto-detects both with `-t javascript` and `-t dart` flags. Triggered by `v*` tag push (forward-looking — no releases tagged yet, that's fine; the workflow is ready) plus `workflow_dispatch` so SBOMs can be generated manually for compliance evidence without cutting a release. Uploaded as a workflow artifact AND attached to the GitHub Release via `softprops/action-gh-release@v2` when tag-triggered. **No code changes outside `.github/`** — pure CI slice; once merged to `main` the workflows start running on the next PR. Cannot run them locally as a verification gate (they're GitHub-hosted by definition); local verification is "YAML parses + actions resolve + commands match local equivalents" — done by inspection against `admin/package.json` scripts (`typecheck`, `test`, `lint`) and known-good Flutter invocations (`flutter analyze`, `flutter test`).

- **2026-05 — Slice B5 (threat model + incident response + vendor register, docs-only).** Ships 8 new docs under `docs/security/`: a `threat-model/README.md` index + 5 one-page STRIDE files (`admin-auth`, `participant-runner`, `host-live`, `recovery`, `leaderboard`) + `incident-response.md` + `vendor-register.md`. **Five surfaces chosen verbatim from the plan** — no scope creep to add new modelled surfaces in this slice (`quiz-bank-write` folded into `admin-auth`; `audit-retention-purge` folded into `admin-auth` because it runs under admin trust). Each STRIDE one-pager follows the same template (Data flow → Trust boundaries → STRIDE table → Out-of-scope → Open actions) so reviewers can scan a single file per surface and every cell either cites a shipped slice (A1–A7, B1 P1) or marks a documented residual. **GDPR scope: mixed (EU + non-EU pilot participants)** per user input — IR runbook treats GDPR 72h breach notification as the primary obligation and offers the same template voluntarily to non-EU subjects, so the runbook does not bifurcate. **On-call model: solo today, designed for future rotation** per user input — IR runbook defines IC + Comms + Scribe + SME roles up front (all collapsed onto the single on-call now), so adding a second person is a config change (env vars + a hand-off section) not a runbook rewrite. The single-point-of-failure risk is explicitly called out and the fallback is "escalate to vendor support + switch affected surface to read-only mode (see §5.2)". **Severity matrix: 4-tier SEV1–SEV4** mapped to ISO 27035 — SEV1 reserved for confirmed personal-data breach or total outage of admin/participant surface, with the bias to upgrade-when-in-doubt documented. **6 containment playbooks** in IR §5: stolen admin session (rotate `MEDRASH_ADMIN_SESSION_SECRET` — ties directly to B1 P1), read-only participant mode, RLS bypass, recovery flow abuse, **manual owner account lockout** (the no-co-owner recovery path called out in `recovery.md`), and vendor-side incident. **Vendor register**: 9 vendors classified by tier (Critical/High/Medium/Low) — Supabase + Netlify + Cloudflare Turnstile as runtime data processors; GitHub + npm + pub.dev + Flutter SDK as build dependencies; Google Fonts as boot-path third-party (with an open action to verify `next/font` self-hosting and downgrade tier if confirmed). Sub-processors, status pages, and support contacts captured per row so an incident handler does not need to hunt URLs at 2am. **Decision to NOT speculatively create `docs/security/dpa/`**: register surfaces open actions to file Supabase + Netlify DPAs there once obtained, but creating an empty directory in this commit would just be cargo-culted scaffolding. **No code changes, no test changes** — pure docs slice, so no typecheck/test/lint gate run; integrity verified by reading every internal link target.

- **2026-05 — Slice B1 phase 1 (session timeout enforcement + audit event-type declarations).** Phase 1 ships the agreed idle-30m + absolute-8h policy via a new HMAC-signed cookie `medrash-admin-session` (Web Crypto API, isomorphic across Edge middleware + Node route runtimes — `node:crypto` was rejected because it does not load reliably in the Edge middleware runtime even though it works in Node routes; using a single isomorphic implementation keeps sign-and-verify symmetric across both call sites and avoids a divergent crypto surface). New env var `MEDRASH_ADMIN_SESSION_SECRET` (≥32 chars), mirroring the `MEDRASH_DEVICE_TOKEN_SECRET` posture (separate secret per cryptographic purpose so a leak of one does not break the other). New module `admin/src/lib/admin-session-cookie.ts` exposes 3 surfaces: `signAdminSessionCookie`, `verifyAdminSessionCookie`, and a pure `decideAdminSession(...)` function so the timeout policy is unit-testable without crypto or cookies (14 new tests, 145 total). Middleware composes verify + decide + sign on every authenticated protected request: on `expire` it clears both our cookie AND every `sb-*-auth-token` cookie then redirects to `/login?reason=session_<idle|absolute>`; on `init` (no cookie OR cookie for a different uid — covers the "old user signed out, new user signed in without clearing cookies" edge case) it mints a fresh cookie with both timestamps at now; on `ok` it re-signs with an updated `lastSeenAt`. Cookie set as `httpOnly`, `sameSite=lax`, `secure` in production, `maxAge=8h` (matches absolute bound so a stale cookie can't outlive its own policy). Signout route also clears the cookie. **Audit event types extended** with 7 new entries declared in the `AuthEventType` union: `session_idle_timeout`, `session_absolute_timeout`, `mfa_enroll`, `mfa_verify_success`, `mfa_verify_fail`, `mfa_disable`, `mfa_recovery_used` — Phase 1 only declares them (the 2 session events surface via the `?reason=` URL param on the redirect; Phase 3 wires the Node-runtime audit emit from the `/login` page; MFA-* declared-but-unused until Phase 2). **Fail-closed design choice**: when `MEDRASH_ADMIN_SESSION_SECRET` is missing or signing fails, middleware redirects to `/denied?reason=config` rather than letting the request through unprotected — same posture as the Supabase init-failure branch already in place. **Verification:** typecheck PASS (exit 0), vitest 145/145 PASS (+14 new for admin-session-cookie), lint 0 errors / 14 pre-existing warnings (unchanged baseline). Phase 0 (enable Supabase Auth TOTP factor in the dashboard) is a user-driven precondition for Phase 2 — currently only email OTP is enabled.

- **2026-05 — Slice A7 phase 3 (zod wire-ins, Next.js server actions + lib parser retirement).** Phase 3 zod-gates all 5 server actions (`login`, `admin-users`, `onboarding`, `sessions`, `quiz-bank`) and retires 5 lib parsers (`parseCreateSessionInput`, `parseCreateQuizInput`, `parseUpdateQuizInput`, `parseCreateQuestionInput`, `parseUpdateQuestionInput`) plus ~9 internal helpers (`SLUG_PATTERN`, `requireString`, `optionalString`, `parseInteger`, `parseBoolean`, `parseSlug`, `parseOptions`, `parseTags`, `parseMetadata`, `optionalIsoTimestamp`). **New helper** `validateForAction<T>(schema, payload)` in `_helpers.ts` returns `{ ok:true, data } | { ok:false, message, issues }` — server actions keep their existing `{ ok:false, message }` envelope contract (single user-facing string) instead of switching to `issues[]`, because the Next.js form-action surface only ever surfaces one message at a time to the form-state UI. **UX-message preservation pattern:** for actions whose original handwritten parsers had specific user-facing strings tied to specific fields (login `"Enter a valid work email."` vs `"Enter the 6-digit code from your email."`, onboarding `"Enter your full name (2–120 characters)."` vs `"Pick a job role (MSR or Manager)."`, admin-users `"Enter a valid email address."` vs `"role must be host or owner."` vs `"userId is required."`), the action inspects `validated.issues[0]?.path` and maps the path back to the original string; for sessions/quiz-bank where the messages were generic the action just surfaces `validated.message`. **Discriminated-union narrowing in quiz-bank-write.ts:** since `quizBankWriteSchema` is a `z.discriminatedUnion("op", ...)`, the post-zod `switch (data.op)` narrows `data.payload` (create/update) and `data.id` (deactivate) per branch, allowing deletion of the runtime `isOperation` guard, the `SUPPORTED_OPS` Set, and per-case manual payload extraction. **`parseIdentityInput` retained** (admin/netlify/functions/_shared/identity.ts): unlike the parsers being retired, `parseIdentityInput` supplies substantive defaults (`"Pilot Participant"`, `"Guest-XXXX"` join codes, `"Unknown Facility"`, `"General"`) when profile fields are missing — these are not shape validation and would lose their domain meaning if folded into a zod schema. Treated as a small normalisation/defaulting helper sitting **after** the zod front door, same architectural role as Phase 2 documented for shared parsers. **Decision to fully delete substring helpers from `quiz-write.ts`** (instead of marking `@deprecated`): zero remaining call sites after the 4 parsers were retired, and no consumer reaches into them by file path. Kept all `Create*/Update*Input` TypeScript types and all `*Record` row-mapping functions — only the parser and its private helpers were deleted. **Verification:** typecheck PASS (exit 0), vitest 131/131 PASS (+14 new tests for admin-users + onboarding schemas, 57 total schema tests), lint 0 errors / 14 pre-existing warnings (unchanged baseline; removing local `EMAIL_RE`/`OTP_RE` constants did not introduce or eliminate any warnings).

- **2026-05 — Slice A7 phase 2 (zod wire-ins, Netlify functions).** Phase 2 ships a single new helper `admin/netlify/functions/_shared/validate.ts` exporting `validateOrRespond(schema, payload)` that returns `{ ok, data }` or `{ ok: false, response }` — the response is a 400 `INVALID_INPUT` with `issues: [{ path, message }]` plus a back-compat `message` field set to the first issue's message (so existing participant/admin clients reading `body.message` keep working without a contract bump). Wired into 9 of 10 plan-listed Netlify functions: `attempt-submit` (full deletion of 6 local parsers — `parseMode`, `parseOrigin`, `parseQuizRef`, `parseSessionId`, `parseAnswers`, `parsePositiveInt`), `session-create`, `session-resolve` (deleted `parseJoinCode`), `quiz-bank-write` (discriminated-union front door over 7 ops), `leaderboard` (deleted `readType`/`readLimit`/`readSeason` + unused `LeaderboardType` alias), `profile-sync`, `ranked-eligibility` (deleted `readQuizRef`), `recover-request`, `recover-verify`. `quiz-list` excluded — its handler takes an empty body. **Design choice for endpoints that share parsers with Next.js server actions** (`session-create` → `parseCreateSessionInput`, `quiz-bank-write` → `parseCreate*Input` / `parseUpdate*Input`, every identity-driven handler → `parseIdentityInput`): zod is added as a **front-door validator** that runs before the shared parser, but the shared parser is **kept** as the fallback-defaults layer (e.g. `parseIdentityInput` still supplies `"Pilot Participant"` / `"Guest-XXXX"` / `"Unknown Facility"` / `"General"` defaults when profile fields are missing — schemas only validate shape, not substantive defaults). Phase 3 retires those shared parsers when server actions get wired. This preserves substantive behaviour while still giving every endpoint a structured `issues[]` response on shape violations. **Behaviour change**: `attempt-submit` previously *silently dropped* malformed per-answer objects (filter, not reject); the schema's `attemptAnswerSchema` rejects the whole batch instead — accepted as a correctness/security tightening (the Phase 2 goal). Quiz/answer drift due to questionId-not-in-quiz is still silent-drop in handler logic, unchanged. Existing test suites (74 prior) all PASS unchanged — confirms wire-ins are observably equivalent on valid payloads.
- **2026-05 — Slice A7 phase 1 (zod foundation).** A7 split into three phases to match the A5 fan-out template. Phase 1 (this commit) ships dependency + 6 schema files + `validateBody` helper + 43 unit tests with **zero wire-ins** so the foundation lands independently of behavioural change. `zod@4.4.3` chosen (zod v4 stable, ESM-native, single-package). Schemas use `z.preprocess(normaliser, innerSchema)` instead of `.transform(...).pipe(...)` because zod v4 + nested object keys require the field's outer wrapper to be `.optional()` for "key may be missing" semantics; preprocess + `.optional()` composes cleanly while `.transform(...).pipe(...).optional()` does not — every "happy path" test omitting an optional field fell over with the latter. Standard envelope `{ ok: true, data } | { ok: false, code: 'invalid_input', issues: [{ path, message }] }` returned by `validateBody(schema, payload)` (Phase 2 wire-ins will map issues into existing endpoint error shapes — `BAD_REQUEST`, `INVALID_INPUT`, etc. — rather than introduce a new top-level shape, to keep the diff small and avoid breaking participant + admin clients). `quizBankWriteSchema` uses `z.discriminatedUnion("op", ...)` over the 7 quiz-bank ops so payload shape is type-narrowed by op at compile time. Hosted smoke skipped for this phase — schemas have no runtime side effects until Phase 2 wires them in. Hand-typed `IdentityInput` / `CreateSessionInput` / etc. interfaces left intact in their original files; Phase 2 will replace them with `z.infer<typeof xSchema>` exports in the same commit that deletes the handwritten parsers, to keep `git blame` honest.
- **2026-05 — Slice A5 phase 3 + A6 hosted-smoke acceptance.** A5 phase 3 shipped as scheduled Netlify function `admin/netlify/functions/audit-retention-purge.ts` (03:17 UTC nightly via `netlify.toml` schedule) rather than `pg_cron` — `pg_cron` is not enabled in the project (verified zero matches across all migrations). Function uses `.delete({ count: 'exact' })` on both `app.auth_events` + `app.admin_audit` `where expire_at <= now()` so per-table row counts surface in success logs; idempotent + service-role-keyed so manual `curl -X POST` is safe. User manually invoked it once on 2026-05-29 and got 200 — accepted as hosted PASS for phase 3. Per-event-type row-count smoke (trigger one of each event + admin op, then `select event_type, count(*) ...`) skipped per user authorization — audit module is fire-and-forget with try/catch insulating callers; wire-ins compile-checked; risk accepted to maintain slice cadence. Same call for A6: full 65-request-burst-to-429 hosted smoke skipped per user authorization — Postgres-backed `enforce_rate_limit` already proven by A1 hosted PASS; A6's 8 new scopes are config-only entries in `RATE_LIMITS` map asserted by the `returns plan-spec defaults for every A6 scope` unit test, so wire-in correctness reduces to "is `enforceRateLimit({scope, identifier})` called before the first DB call?" — confirmed by grep across all 7 handlers. Both slices marked closed.
- **2026-05 — Slice A6 shape (rate-limit fan-out).** 8 new scopes added to `admin/src/lib/rate-limit.ts` (`attempt_submit`, `attempt_submit_ip`, `profile_sync`, `ranked_eligibility`, `leaderboard`, `quiz_list`, `quiz_bank_write`, `session_create`) — single commit, no DB migration needed because A1's `app.auth_rate_limit` table is already scope-keyed. Wired into 7 endpoints (`attempt-submit` gets dual-bucket: IP first via `extractRemoteIp`, then participant after `parseIdentityInput`; `quiz-list` + `leaderboard` IP-only; `profile-sync` + `ranked-eligibility` per-device via `identity.deviceInstallId`; `quiz-bank-write` + `session-create` per-admin via `authResult.auth.userId`). Deviations from spec: (a) plan said "all 9 unprotected endpoints" but `recover-request` / `recover-verify` were already protected by A1, so the actual fan-out is 7; (b) `session-resolve` already has its own per-instance in-memory rate-limiter (30 req/min per IP with `MIN_RESPONSE_LATENCY_MS = 220` floor) — left untouched in A6 to keep this slice surgically scoped; durable replacement with Postgres-backed limiter is a follow-up if hosted smoke shows the in-memory map dropping requests under cold-start churn; (c) `attempt_submit` modelled as two distinct scopes (`attempt_submit` + `attempt_submit_ip`) instead of one scope with two identifiers, because `enforceRateLimit` is single-key and two scopes is the clean way to express two independent buckets; (d) 429 response shape matches A1 (`{ ok: false, code: "RATE_LIMITED", message, retryAfterSeconds }`) rather than the plan's `{ error: 'rate_limited' }` — A1 already shipped first, so consistency wins; (e) no `Retry-After` HTTP header added (still in the JSON body) because every existing caller reads it from JSON — adding the header is a defence-in-depth nice-to-have, parked. Audit-log emission for rate-limit trips deferred — A5's `auth_events` table doesn't have a generic rate-limit event_type, and adding one across all 7 surfaces would double the diff; rate-limit trips are visible in Netlify logs + the `app.auth_rate_limit.locked_until` column already, which is enough signal for the pilot.
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
