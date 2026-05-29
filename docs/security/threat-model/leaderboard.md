# STRIDE — Leaderboard (public + per-session)

**Surface**: `admin/netlify/functions/leaderboard.ts` + `ranked-eligibility.ts` + Supabase materialised views (migration 002).
**Last reviewed**: 2025-01 (initial draft, Slice B5).
**Related slices**: A1 (rate limits), A3 (RLS), A7 (zod), B7 (anomaly detection — planned).

## Data flow

`Anyone → /leaderboard?session=… → Edge cache (Netlify) → Postgres materialised view → JSON response with capped row count.`

For ranked-eligibility (cross-session ranking): admin-only call that consults the same materialised view plus per-user opt-in flag.

## Trust boundaries

| # | Boundary | Crossed by |
|---|---|---|
| 1 | Internet → leaderboard function | Session ID (untrusted), optional bearer (for personalised "your rank" overlay) |
| 2 | Function → Postgres MV | Service-role read on a denormalised view — no per-user JWT path |
| 3 | Function → response | Capped to top-N + the bearer's own row if present |

## STRIDE

| Threat | Vector | Mitigation (file) | Residual |
|---|---|---|---|
| **S** Spoofing | Forged session ID returns another tenant's leaderboard | Session ID validated via zod (A7) as UUID; MV row scoped by session_id; no cross-session join on public path. | None. |
| **T** Tampering | Reordering via cache-poisoning | Edge cache keyed on full URL including session ID; payload signed by Netlify edge (TLS) — no client-side mutability. | None. |
| **R** Repudiation | "I was #1, the leaderboard says I'm #4" | Underlying `attempts` rows are append-only and timestamped; MV refresh is on a known schedule; deterministic tie-breaker (earliest finish time). | None — disputes are resolved by re-running the rank query on raw attempts. |
| **I** Information disclosure | PII leak via leaderboard payload | Payload contains only `display_name` (already non-PII per onboarding consent) + score + rank; no email, no device ID, no IP. | Display name collisions visible — accepted (it's a leaderboard). |
| **D** Denial of service | Scraping all session IDs in a tight loop | Edge cache absorbs identical reads; per-IP rate limit on leaderboard endpoint (A1); session IDs are UUIDs (unguessable). | Targeted DoS on a specific live session's MV refresh = back to cached snapshot until refresh succeeds. |
| **E** Elevation of privilege | Public reader influences ranking outcome | No write path from leaderboard endpoint; MV is read-only; rebuild script runs server-side. | None. |

## Out of scope

- Cross-session aggregate ranking (ranked-eligibility): admin-only, covered by [admin-auth.md](admin-auth.md) trust model.
- Score computation correctness: product-spec concern, not a security threat.

## Open actions

- [ ] B7 — anomaly detection job: flag sessions where >X% of attempts share identical answer vectors (collusion signal).
