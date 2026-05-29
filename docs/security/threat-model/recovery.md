# STRIDE — Account recovery (admin email recover flow)

**Surface**: `admin/src/app/recover/` UI + recover-request + recover-verify server actions + admin reinvite path.
**Last reviewed**: 2025-01 (initial draft, Slice B5).
**Related slices**: A1 (rate limits), A5 (audit), A6 (Turnstile on recover-request), A7 (zod on both actions), B1 P3 (owner-resets-other-owner step-up — planned).

## Data flow

`User → /recover (Turnstile + email) → recover-request → Supabase Auth email link / OTP → /recover/verify → new session issued.`

For owner role: if the locked-out account is an owner AND no other owner is available, recovery escalates to **manual** path via incident-response runbook (cannot be self-served).

## Trust boundaries

| # | Boundary | Crossed by |
|---|---|---|
| 1 | Internet → recover-request | Email address (untrusted) + Turnstile token |
| 2 | Email inbox → recover-verify | Single-use OTP/link bound to email |
| 3 | recover-verify → admin allowlist | New session must still pass allowlist (A4) — recovery cannot grant a role |

## STRIDE

| Threat | Vector | Mitigation (file) | Residual |
|---|---|---|---|
| **S** Spoofing | Attacker initiates recovery for a real admin's email; tries to brute-force OTP | Turnstile on recover-request (A6); per-email + per-IP rate limit (A1); Supabase OTP is 6-digit single-use with 60-second resend cooldown. | Successful inbox takeover = recovery succeeds. Mitigated by B1 P2 TOTP: even with a fresh session, owner-only actions require TOTP. |
| **T** Tampering | Modified recover-verify payload (skip the OTP check) | zod schema (A7) requires `email + code` shape; Supabase verifies OTP server-side — Next.js cannot bypass. | None. |
| **R** Repudiation | User denies initiating a recovery they did initiate | recover_request_initiated, recover_request_succeeded, recover_request_failed audit events (A5). | None. |
| **I** Information disclosure | Enumeration of valid admin emails via differing error responses | Both "valid email recovery sent" and "no such email" return the same generic success message; timing-equalized via constant work in handler. | A patient attacker may infer membership via OTP-delivery latency. Documented residual. |
| **D** Denial of service | Recovery flood locks a real admin out (OTP cooldown) | Per-email rate limit (A1) caps to N/hour; admin can use the manual incident-response path to bypass. | Adversary can degrade self-serve recovery; manual path remains. |
| **E** Elevation of privilege | Recovery used to grant a role rather than restore one | Recovery only issues a fresh session for an already-allowlisted user; if user is not on allowlist, login still fails at the middleware step (A4); role grants always go through the explicit admin-users action which logs and (B1 P3) step-ups TOTP. | None — recovery cannot mint privilege. |

## Manual owner recovery (locked-out owner, no co-owner)

Defined in [../incident-response.md §55](../incident-response.md#55-runbook-owner-account-lockout-no-co-owner). High-level:

1. Verify identity out-of-band (video call + government ID).
2. Use Supabase dashboard service-role to insert into `admin_users` and rotate `MEDRASH_ADMIN_SESSION_SECRET` (invalidates all sessions).
3. Have the recovered owner re-enrol TOTP from clean device.
4. File post-incident review within 7 days.

## Open actions

- [ ] B1 P3 — owner-resets-other-owner step-up TOTP.
- [ ] Document timing-equalization technique applied to recover-request error responses (low-priority; once B3 ships).
