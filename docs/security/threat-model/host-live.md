# STRIDE — Host live (live session UI + lifecycle)

**Surface**: `admin/src/app/sessions/` UI + `admin/netlify/functions/session-create.ts` + scoring/end-session server actions.
**Last reviewed**: 2025-01 (initial draft, Slice B5).
**Related slices**: A3 (RLS), A4 (admin allowlist), A5 (audit), A7 (zod on session-create + end-session).

## Data flow

`Admin browser (authed) → server action createSession → /session-create → Postgres sessions table → QR/code rendered → participants resolve → admin ends session → final scoring batch.`

## Trust boundaries

| # | Boundary | Crossed by |
|---|---|---|
| 1 | Admin browser → Next.js server action | Signed admin session + auth cookie |
| 2 | Server action → Netlify function | Service-role internal call (no extra hop in MVP — actions write directly under user JWT for RLS) |
| 3 | Live session → participants | QR + 6-char code over screen + (optional) projector |

## STRIDE

| Threat | Vector | Mitigation (file) | Residual |
|---|---|---|---|
| **S** Spoofing | Imposter "admin" starts a session; participant joins wrong session | Server-action allowlist check (A4); session code includes Postgres-generated random suffix; session_join_events records `(session_id, device_id, joined_at)` for audit. | If two sessions are open with overlapping codes (32^6 collision space), the wrong-session join is theoretically possible. Mitigated by checking code uniqueness at create time (migration 003). |
| **T** Tampering | Modified end-session payload (skip a participant) | Server-side scoring batch runs over `attempts` table directly; admin's "end" call only flips `sessions.status`; no client-supplied score list. | None for scoring path. |
| **R** Repudiation | Admin denies starting/ending a session | Audit log writes for session_create, session_end, session_code_rotate (A5); session row has `created_by` FK to admin user. | None. |
| **I** Information disclosure | QR code or session code leaks publicly; participants from outside the room join | Code is short-lived (until session ends); admin can end session at any time; B6 (planned) adds explicit per-session geofence option. | Pilot accepts that code-on-projector is the trust model. Mid-session rotation is the mitigation if leak is detected. |
| **D** Denial of service | Flood of fake session-join attempts; live UI overwhelmed | Per-IP rate limit on session-resolve (A1); leaderboard rendered server-side with capped row count; admin live UI uses Supabase realtime channel with reconnect backoff. | Realtime channel cost spike under DoS = Supabase rate-caps + Netlify edge throttles. |
| **E** Elevation of privilege | Editor admin ends a session they didn't create; non-admin reaches /sessions | Allowlist check + RLS on `sessions` table requires `created_by = auth.uid()` for end/rotate, or `role = 'owner'`. | None known. |

## Out of scope

- Per-question pacing/timing UI: covered in product spec, not a security boundary.
- Participant device authentication: see [participant-runner.md](participant-runner.md).

## Open actions

- [ ] B6 — runbook entry "mid-session code rotation" (link from incident-response.md).
- [ ] B7 — anomaly alert if a single device joins more than N concurrent sessions.
