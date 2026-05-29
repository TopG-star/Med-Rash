# STRIDE — Participant runner (Flutter app)

**Surface**: `app/` Flutter app + `admin/netlify/functions/` participant-facing endpoints (`session-resolve`, `attempt-submit`, `leaderboard`, `ranked-eligibility`).
**Last reviewed**: 2025-01 (initial draft, Slice B5).
**Related slices**: A1 (rate limits), A2 (device tokens), A3 (RLS), A6 (Turnstile on device-token mint), A7 (zod).

## Data flow

`Flutter app → /device-token (Turnstile) → bearer issued → /session-resolve (QR or code) → /attempt-submit (one-shot, idempotent) → /leaderboard (read).`

## Trust boundaries

| # | Boundary | Crossed by |
|---|---|---|
| 1 | Untrusted device → Edge function | Turnstile token on first contact; HMAC bearer thereafter |
| 2 | Edge function → Postgres | Service-role JWT (server only); writes go through guarded RPCs |
| 3 | App-local storage → Edge function | Bearer + nonce — replay-resistant via per-attempt idempotency key |

## STRIDE

| Threat | Vector | Mitigation (file) | Residual |
|---|---|---|---|
| **S** Spoofing | Forged device token, impersonated participant | HMAC-SHA256 device tokens with rotating server secret ([_shared/device-token.ts](../../../admin/netlify/functions/_shared/device-token.ts)); Turnstile on mint (A6); token bound to `deviceId` + `issuedAt`. | Stolen device token before expiry = full participant impersonation for that session. Mitigated by short TTL + per-attempt idempotency. |
| **T** Tampering | Modified attempt payload (boost own score) | Server recomputes score from question bank — client cannot supply a final score; zod schema rejects unknown fields (A7); idempotency key on attempt-submit collapses replays. | Client side-channel timing not authoritative — server clock is source of truth. |
| **R** Repudiation | Player claims they never submitted; admin claims they did | Attempts table append-only with server-side timestamps; session_join_events log (migration 005) records every entry; bearer claims include `iss` + `iat`. | None for individual attempts. Aggregated leaderboard rebuilds reproducible from raw attempts. |
| **I** Information disclosure | Quiz answer key leak; other participants' attempts visible | Quiz-bank-write is admin-only (RLS — A3); participant reads filtered to own attempts + aggregated leaderboard; no per-row PII in leaderboard payload. | Answer key is shipped to client only as it's served per question — full bank never sent at session start. Verified in `/quiz-list` payload shape. |
| **D** Denial of service | Mint-token flood, attempt flood, leaderboard scrape | Turnstile on mint (A6); per-IP + per-token rate limits on attempt-submit + leaderboard (A1); Netlify edge caching on leaderboard reads. | Targeted attack on a single live session would force operator to rotate session code (manual). |
| **E** Elevation of privilege | Participant accesses admin endpoints | Bearer scope claims separate `participant` from `admin`; admin endpoints require Supabase user JWT (different cookie); RLS rejects service-role-less queries. | None known. |

## Out of scope

- Anti-cheat (peer collusion, second device): explicitly out of scope for pilot; documented in [prd.md](../../prd.md). Detection signals (rapid identical-answer patterns) recorded in audit log for later analysis.
- Native binary tampering of Flutter app (rooted device): accepted residual; pilot is supervised.

## Open actions

- [ ] B6 — explicit session code rotation runbook (admin-driven, mid-session).
- [ ] B7 (planned) — anomaly detection job on attempts table.
