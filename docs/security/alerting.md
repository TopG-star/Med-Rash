# Alerting Thresholds & Routing

> Slice B7 (Pillar 6) — defines when monitoring sources page an on-caller and where the page lands.
>
> Standards: ISO 27002 §8.15 (logging), §8.16 (monitoring activities), NIST CSF DE.CM-1 (network monitored to detect potential cybersecurity events).

---

## Sources of truth

| Signal | Source | Owner |
|---|---|---|
| Admin app exceptions + perf | Sentry project `medrash-admin` (browser + Node + Edge runtimes) | Engineering |
| Participant app exceptions | Sentry project `medrash-app` (Flutter Web) | Engineering |
| Auth event spikes | Supabase table `app.auth_events` (filled by Slice A5 P2) | Security |
| Audit-write failures | Netlify Function logs for `attempt-submit`, `session-resolve`, etc. | Engineering |
| Edge security-header drift | Slice A4 dual-layer (next.config.ts + netlify.toml) — caught by CI | Engineering |
| Backup/restore drill | DR runbook quarterly drill (B6) | Engineering |

The Sentry projects ship with **empty DSNs**. Until the Sentry org is provisioned, the SDK initialises into a no-op and no events leave the runtime — matching the empty-secret posture used for `MEDRASH_ADMIN_SESSION_SECRET` in B1.

---

## Page-worthy thresholds

These are the conditions that **WILL** dispatch a page to `INCIDENT_PRIMARY_EMAIL`. Tune the numbers in Sentry once two weeks of production data has landed.

### Sentry alerts (configured in Sentry org → Alerts)

| Alert | Condition | Window | Channel |
|---|---|---|---|
| New issue (admin) | First-seen issue in `medrash-admin`, environment ∈ {production} | n/a (issue create) | Email → `INCIDENT_PRIMARY_EMAIL` |
| New issue (app) | First-seen issue in `medrash-app`, environment ∈ {production} | n/a | Email → `INCIDENT_PRIMARY_EMAIL` |
| Error-rate spike | `count(events) > 50` in 5min | 5 min rolling | Email |
| Issue regressed | A resolved issue starts firing again | n/a | Email |
| Crash-free session % | `crash_free_sessions < 99%` | 1 hour | Email |
| Perf regression | `p95(transaction.duration) > 4000ms` on `quiz/render` | 15 min | Email (low priority) |

### Supabase-side alerts (Sentry does NOT see these)

| Alert | Source | Threshold | Channel |
|---|---|---|---|
| Auth failure burst | `app.auth_events` rows with `success=false` | `> 20 / minute` from a single IP, **OR** `> 200 / hour` org-wide | Supabase Database Webhook → email |
| Admin session timeout flood | `app.admin_audit` rows with `action='session_expired'` | `> 30 / hour` | Email |
| Backup job failure | Supabase scheduled backups | Any failed run | Supabase native alert → email |

### CI-level alerts (handled by GitHub Actions, Slice B4)

| Alert | Condition | Channel |
|---|---|---|
| Dependency-audit critical/high finding | `npm audit --audit-level=high` exits non-zero | GitHub Checks (blocks merge) |
| Secret leak | `gitleaks` finds a match | GitHub Checks (blocks merge) |
| Drift in CSP between `next.config.ts` and `netlify.toml` | (planned) | GitHub Checks |

---

## Channel + routing

The single canonical channel is the environment variable `INCIDENT_PRIMARY_EMAIL` defined in the [Incident Response](./incident-response.md) doc. Slack/PagerDuty webhooks are deliberately deferred until the team grows past one on-caller.

When that day comes, the planned routing is:

- P0 (active outage / data leak): PagerDuty escalation policy `medrash-p0`
- P1 (single-feature degraded): Slack `#medrash-alerts`
- P2 (background noise, perf regressions): Sentry inbox only, no page

---

## PII discipline for alert payloads

Every Sentry event passes through a shared [PII scrubber](./../../admin/src/lib/observability/sentry-scrubber.ts) (admin) / [Flutter equivalent](./../../app/lib/core/observability/sentry_scrubber.dart) before transmission:

- `user.email` / `user.username` / `user.ip_address` stripped
- Cookies + `Authorization` headers redacted
- URL query strings + fragments dropped from breadcrumbs
- Email-shaped substrings in error messages replaced with `[email-redacted]`
- Strings longer than 2048 chars truncated

`sendDefaultPii` is `false` everywhere — the scrubber is defence-in-depth, not the primary control.

---

## Verification checklist (review quarterly)

- [ ] `SENTRY_DSN` set in admin Netlify + `NEXT_PUBLIC_SENTRY_DSN` set in admin Netlify
- [ ] `SENTRY_AUTH_TOKEN` + `SENTRY_ORG` + `SENTRY_PROJECT` set in admin Netlify (for source-map upload)
- [ ] `SENTRY_DSN` set in participant Netlify (Flutter web)
- [ ] All alerts above exist in the Sentry org, environment filter = `production`
- [ ] Supabase auth-event webhook ships to `INCIDENT_PRIMARY_EMAIL`
- [ ] Test page received by on-caller within last 30 days (manual trigger)
