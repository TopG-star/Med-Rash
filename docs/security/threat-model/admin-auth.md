# STRIDE — Admin auth (Next.js portal)

**Surface**: `admin/` Next.js app — login, middleware, admin dashboard, server actions.
**Last reviewed**: 2025-01 (initial draft, Slice B5).
**Related slices**: A4 (admin allowlist), A5 (audit log), A6 (Turnstile), A7 (zod), B1 (session timeout + MFA), B3 (CSP — planned), B4 (IP allowlist — planned).

## Data flow

`Browser → /login (Turnstile + email OTP) → Supabase Auth → /auth/callback → middleware (cookie verify + session timeout) → admin pages → server actions → Postgres (RLS + admin allowlist).`

## Trust boundaries

| # | Boundary | Crossed by |
|---|---|---|
| 1 | Internet → Next.js Edge | login form POST, OTP code |
| 2 | Edge middleware → Node server actions | signed admin session cookie + Supabase auth cookie |
| 3 | Server action → Postgres | RPC under user JWT (RLS enforces admin allowlist) |

## STRIDE

| Threat | Vector | Mitigation (file) | Residual |
|---|---|---|---|
| **S** Spoofing | Stolen OTP, stolen session cookie, stolen auth cookie | Turnstile on /login (A6); HMAC-signed admin session cookie tied to `userId` ([admin-session-cookie.ts](../../../admin/src/lib/admin-session-cookie.ts)); cookie cleared on uid mismatch; cookies `httpOnly + secure + sameSite=lax`; B1 P2 adds TOTP step-up for owner. | Pre-MFA: single-factor email — accepted until B1 P2 ships. |
| **T** Tampering | Forged session cookie to extend lifetime | HMAC-SHA256 with `MEDRASH_ADMIN_SESSION_SECRET` (≥32 chars); absolute 8 h + idle 30 min enforced server-side regardless of cookie claims; fail-closed on missing secret → `/denied?reason=config`. | None known. |
| **R** Repudiation | Owner denies an admin action | Audit log writes for login_success, login_failure, signout, role changes, session_idle/absolute_timeout, mfa_* (A5 + B1); append-only with 1-year retention. | Audit DB itself trusted; off-box export to S3/Glacier is a follow-on. |
| **I** Information disclosure | Admin pages leak PII or quiz answers to wrong tenant | RLS on every table (A3); admin allowlist check on every server action (A4); zod input validation (A7); B3 CSP (planned) limits exfil channels. | Pre-CSP: inline script XSS could read admin DOM. Mitigated by Next.js default escaping; full lockdown waits on B3. |
| **D** Denial of service | OTP flood, login brute force, Edge cost spike | Per-email + per-IP OTP rate limits (A1); Turnstile (A6); Netlify/Vercel platform DDoS at edge. | Distributed Turnstile-bypass campaign would still cost OTP credits — covered by Supabase rate limits. |
| **E** Elevation of privilege | Editor escalates to owner; non-admin lands on admin page | Allowlist check on every server action AND in middleware redirect; RLS prevents direct table writes even with valid JWT; B1 P2 forces TOTP for any owner-only mutation (e.g., role grants). | Pre-MFA: a stolen owner session = full owner. Documented residual until B1 P2. |

## Out of scope (covered elsewhere)

- Account recovery: see [recovery.md](recovery.md).
- Host live actions invoked from the admin portal: see [host-live.md](host-live.md).
- Vendor/SaaS supply chain risk: see [../vendor-register.md](../vendor-register.md).

## Open actions

- [ ] B1 P2 — TOTP enrolment + hard block for owner.
- [ ] B3 — CSP + Trusted Types.
- [ ] B4 — IP allowlist for /admin in production.
