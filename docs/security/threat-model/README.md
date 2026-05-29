# MedRash Threat Model

> Slice B5 of [`security-hardening-plan.md`](../../security-hardening-plan.md). One-page STRIDE per surface.

## Scope

Five attacker-visible surfaces are modelled. Each one is a separate one-page STRIDE so a reviewer can scan a single file per surface.

| Surface | File | Owner | Primary asset |
|---|---|---|---|
| Admin auth (Next.js portal) | [admin-auth.md](admin-auth.md) | Product | Owner role privileges |
| Participant runner (Flutter app) | [participant-runner.md](participant-runner.md) | Product | Per-device bearer token + attempt integrity |
| Host live (live session UI + create/end session) | [host-live.md](host-live.md) | Product | Session lifecycle + scoring authority |
| Account recovery (email recover flow) | [recovery.md](recovery.md) | Product | Account takeover surface |
| Leaderboard (public + per-quiz) | [leaderboard.md](leaderboard.md) | Product | Read-side data exfiltration |

## Method

1. **Data flow**: 1-line description of who sends what to where.
2. **Trust boundaries**: where signed/unauthenticated input crosses into trusted code.
3. **STRIDE**: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege. For each: the threat, the mitigation in MedRash (with file references), and any residual risk left unmitigated.

Every mitigation references either a shipped slice (A1–A7, B1 P1) or a planned slice. If a row says "residual: accepted", the call has been recorded in the [Decisions Log](../../security-hardening-plan.md#8-decisions-log).

## Review cadence

- **Per slice**: any A-block or B-block slice that touches a modelled surface MUST update the corresponding one-pager in the same commit.
- **Quarterly**: full re-read by the owner; mark each file's `Last reviewed` date.
- **On incident**: any SEV1 or SEV2 incident triggers a forced re-read of the affected surface within 7 days, per [incident-response.md §6](../incident-response.md#6-post-incident).

## Standards mapping

- ISO 27001 §6.1.2 (risk assessment), §A.5.7 (threat intelligence)
- ISO 27002 §5.7, §5.19–5.30 (supplier + threat management)
- NIST CSF GV.RM (risk management), ID.RA (risk assessment)
- GDPR Art. 32 (security of processing) — informs the Information Disclosure rows
