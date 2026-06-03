# MedRash pilot runbook

Operational reference for the first live pilot. Three audiences,
three sections — find your role, then follow the lane. Nothing
here replaces the [hosted deploy checklist](./hosted-deploy.md);
this document assumes the admin app and Supabase project are
already provisioned and verified.

Conventions used below:
- `<admin-origin>` — the admin app URL (e.g. `https://medrash-admin.netlify.app`).
- `<app-origin>` — the participant Flutter web app URL.
- All times shown in UTC unless stated otherwise.

---

## 1. Sales rep workflow (participant)

The rep never logs into the admin app. Their full journey:

1. **Join the session.** The manager sends a join URL or QR code of the
   shape `${app-origin}/session/<CODE>`. Open it on phone, set the
   nickname, accept the Turnstile challenge (one tap), tap Join.
2. **Take the quiz.** Questions appear one at a time, 4 options each.
   Tap to select, tap Next to advance. Progress persists if the tab is
   backgrounded.
3. **Submit.** The final tap submits the entire attempt. The leaderboard
   appears within ~5 s. Their nickname + score + rank are shown.

### "I see Pending Sync" — what to do

This pill appears under the leaderboard when the device successfully
queued the attempt locally but the network call to `/attempt-submit`
or `/profile-sync` did not finish (timeout, captive portal, flight mode).
The outbox (Slice P0.1) keeps the payload in `SharedPreferences` under
`medrash.outbox.v1` and retries automatically with exponential backoff.

Tell the rep:
- Stay on the page for ~30 s with a working network connection. The pill
  clears when the outbox drains.
- If the pill persists for > 2 min on a known-good connection, refresh
  the page once. The outbox survives the refresh.
- If it still persists after the refresh, capture a screenshot and DM
  the host. The attempt is not lost — it ships on the next successful
  network round-trip.

The outbox caps at 200 entries / 256 KB. A 4xx response drops the entry
permanently (bad payload, no point retrying); a 5xx retries up to 6
times then gives up.

---

## 2. Manager workflow (admin)

Managers log in to `<admin-origin>` via Supabase magic-link. Their
allowlist row in `app.admin_users` must have `role = 'manager'` or
`role = 'superadmin'` and `is_active = true`.

### Creating a session

1. Navigate to **/sessions** → **New session**.
2. Pick the quiz, set the start/end timestamps, pick a facility (optional
   — used for `/reports` facility roll-ups).
3. Submit. The created session displays a 6-character join code and a
   QR code linking to `${app-origin}/session/<CODE>`.
4. Share the QR via the on-screen download button or the
   "Copy join URL" button.

The function path is `/.netlify/functions/session-create`. It is
idempotent on the `Idempotency-Key` header — re-clicking Submit within
24 h with the same body is a safe no-op (Slice P0.2).

### Watching the leaderboard live

While the session is active, the **/sessions/<id>** page polls the
leaderboard every ~10 s. The same data is reachable as JSON at
`/.netlify/functions/leaderboard?sessionId=<id>` for embedding into
post-event displays.

### Exporting reports

`/reports` exposes five exports:

| Export | Default rows | Hard cap |
| --- | --- | --- |
| Attempts | 5 000 | 50 000 |
| Answers | 10 000 | 100 000 |
| Most-missed questions | 50 | 500 |
| Facility performance | 50 | 500 |
| Treatment perception | 50 | 500 |

All five render as buffered CSV by default. For exports anywhere near
their hard cap, append `?stream=1` to the URL to use the streaming path
— it ships row-by-row without holding the full document in function
memory (Slice P0.7). Excel + Numbers + Google Sheets all open the
streamed file unchanged (UTF-8 BOM preserved).

### Filters

Reports accept `?startsAt=`, `?endsAt=`, `?facility=`, `?specialty=`,
`?sessionId=`, `?quizId=`. The UI builds these from the picker; the URL
is sharable.

---

## 3. Host troubleshooting (engineering on-call)

### 3.1 Rate-limit 429 from a function

Rate limits are enforced via `app.enforce_rate_limit(...)` (migration
013). Scopes + ceilings live in [admin/src/lib/rate-limit.ts](../admin/src/lib/rate-limit.ts):

| Scope | Limit | Window | Lockout |
| --- | --- | --- | --- |
| `session_resolve` | 30 | 60 s | 60 s |
| `device_token` | 10 | 60 s | 60 s |
| `attempt_submit` | (see file) | | |

A `429` response from a function carries a `Retry-After: <seconds>`
header. Confirm whether the caller is a real user or a stuck client by
looking at the `clientFingerprint` value in the function's Netlify
logs — it's hashed but stable per device.

If the limit is genuinely too tight for the pilot, edit the
`RATE_LIMITS` table in that file and redeploy. Do not edit the database
RPC. Do not raise the limit "temporarily" without scheduling its return.

### 3.2 422 IDEMPOTENCY_KEY_REUSED

This means a client sent the same `Idempotency-Key` for a different
request body within the 24 h cache window. Common causes:
- A retry loop that mutates the payload between attempts (a bug).
- Two different users sharing one device install and minting overlapping
  keys (unlikely in pilot scope).

The cache row lives in `app.idempotency_keys`. To clear a specific key
for re-submission:

```sql
delete from app.idempotency_keys
where scope = 'session_create'
  and key = '<the key the client logged>';
```

The whole table is drained nightly by the audit purge (see
[hosted-deploy.md §7](./hosted-deploy.md#7-audit-retention-purge-scheduled)).

### 3.3 Sentry triage

DSN is set per-runtime in `admin/sentry.*.config.ts` and on the Flutter
side via `SENTRY_DSN`. Active alert routes:

- `function:audit-retention-purge` — purge failure.
- `function:session-create` / `function:quiz-bank-write` — write-path
  errors. Investigate idempotency conflicts and rate-limit storms here.
- Browser CSP report alerts arrive via `/api/csp-report`; they log to
  the server console as `[csp-report] directive=… blocked=… doc=…`.
  Aggregate via Netlify function logs grep — a sudden spike means a
  third-party script was added without updating the CSP allowlist in
  `admin/next.config.ts` (and the mirrored block in `netlify.toml`).

### 3.4 Audit purge failure

See [hosted-deploy.md §7](./hosted-deploy.md#7-audit-retention-purge-scheduled).
Manual re-run via:

```pwsh
curl -sS -X POST https://<admin-origin>/.netlify/functions/audit-retention-purge
```

If the response is `5xx` with one error string per failed table,
investigate that table directly — usually a Supabase outage or a row
that lost its `expire_at`. Backfill `expire_at` with a one-off SQL
update; do not lower the retention.

### 3.5 Environment-variable checklist (production)

`validateProductionEnv()` runs at admin boot (Slice P0.5) and refuses
to start if any of these are missing or malformed:

- `SUPABASE_URL` (https, ends with `.supabase.co`).
- `SUPABASE_SERVICE_ROLE_KEY` (≥ 40 chars).
- `SUPABASE_ANON_KEY` (≥ 40 chars).
- `MEDRASH_TURNSTILE_SECRET`.
- `MEDRASH_ADMIN_PORTAL_BASE_URL` (https).
- `MEDRASH_APP_PUBLIC_BASE_URL` (https).

The function throws on boot with a redacted error (it names the
offending variable but never echoes its value). If the admin app refuses
to come up after a deploy and the build log shows
`EnvValidationFailure`, fix the env var in Netlify and re-deploy.

### 3.6 Quick health gate

One-line check that the whole stack is alive:

```pwsh
curl -sS https://<admin-origin>/.netlify/functions/health
```

Expected: `200` with `{"ok": true, ...}`. A `5xx` or non-JSON body
means the function bundler or the Supabase round-trip is broken — go
straight to [hosted-deploy.md §3](./hosted-deploy.md#3-local-smoke-test-before-redeploying).
