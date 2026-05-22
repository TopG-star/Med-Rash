# Hosted deploy checklist — Netlify + Supabase

This is the operational runbook for shipping the admin panel
(`admin/`) and its Netlify Functions to production. Treat each
section as a gate — do not skip ahead.

Site under management: <https://thriving-gingersnap-2f2932.netlify.app/>
(rename via Netlify UI once it carries real traffic).

---

## 1. One-time provisioning

### 1.1 Supabase project
1. Confirm project is provisioned and you have:
   - **Project URL** (`https://<ref>.supabase.co`)
   - **Service-role key** (Settings → API → `service_role`)
2. Apply migrations in order via the SQL editor or `supabase db push`:
   - [supabase/migrations/001_initial_schema.sql](../supabase/migrations/001_initial_schema.sql)
   - [supabase/migrations/002_leaderboard_and_analytics.sql](../supabase/migrations/002_leaderboard_and_analytics.sql)
   - [supabase/migrations/003_quiz_product_and_position.sql](../supabase/migrations/003_quiz_product_and_position.sql)
   - [supabase/migrations/004_attempts_season_key_guardrails.sql](../supabase/migrations/004_attempts_season_key_guardrails.sql)
   - [supabase/migrations/005_session_join_events.sql](../supabase/migrations/005_session_join_events.sql)
3. Confirm the `app` schema is exposed in **Settings → API → Schema** so PostgREST + the
   admin client (which runs `db: { schema: "app" }`) can reach it.

### 1.2 Netlify site
1. Site is already created from this repo via the GitHub integration.
2. Add [netlify.toml](../netlify.toml) (this commit) — repo root. It locks:
   - `base = "admin"` (resolves the Next.js project)
   - `publish = ".next"` + `@netlify/plugin-nextjs` (SSR + Route Handlers)
   - `functions = "netlify/functions"` (esbuild bundler)
   - Node 20 build runtime
3. After the next deploy, sanity-check the published surface area:
   ```pwsh
   curl -sS https://thriving-gingersnap-2f2932.netlify.app/.netlify/functions/health
   curl -sS -o $null -w "%{http_code}`n" https://thriving-gingersnap-2f2932.netlify.app/
   ```
   Expect `200` on both. A `404` on root means the Next plugin did not
   run — re-check `base` resolution in the build log.

---

## 2. Environment variables

Set these in **Netlify → Site → Environment variables**. All scopes
unless noted. **Never** commit any of them.

| Variable | Used by | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | admin SSR + functions | e.g. `https://abc123.supabase.co`. Build- and runtime-scoped. |
| `SUPABASE_SERVICE_ROLE_KEY` | admin SSR + functions | **Secret.** Server-only. Never expose to a Client Component. |
| `MEDRASH_GATE_API_KEY` | functions only | Shared header secret consumed by participant-facing endpoints (`quiz-list`, `attempt-submit`, `ranked-eligibility`, `session-resolve`). |
| `MEDRASH_ADMIN_WRITE_KEY` | functions only | Shared header secret for admin-write endpoints (`session-create`, `quiz-bank-write`). |
| `MEDRASH_APP_PUBLIC_BASE_URL` | admin SSR | Origin used to build session join URLs / QR codes. Set to the Flutter app's public origin (not the admin origin). |

Recommended secret hygiene:
- Generate the two `MEDRASH_*_KEY` secrets with `openssl rand -hex 32`.
- Mark `SUPABASE_SERVICE_ROLE_KEY` and both `MEDRASH_*_KEY` as
  **Sensitive** in Netlify so they are not logged in deploy output.

---

## 3. Local smoke test (before redeploying)

From the workspace root, run hosted-check against the live Supabase
project. This validates that the `app` schema is reachable with the
service-role key and all 7 required tables respond.

```pwsh
$env:SUPABASE_URL = "https://<ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "<paste service role here>"
node ./scripts/hosted-check.mjs
```

Expected output: `Connectivity check passed` followed by `Table 'X'
reachable` for users, quizzes, questions, sessions, attempts, answers,
session_join_events. Any failure aborts the deploy plan.

After the run:
```pwsh
Remove-Item Env:SUPABASE_URL
Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY
```

---

## 4. Post-deploy verification

In order — each step gates the next.

1. **Build log** — confirm `@netlify/plugin-nextjs` ran and reported
   the same 10 routes as the local build (`/`, `/_not-found`,
   `/dashboard`, `/intelligence`, `/quiz-bank`, `/quiz-bank/[slug]`,
   `/quiz-bank/new`, `/reports`, `/reports/export/[type]`, `/sessions`).
2. **Static routes** — open `/dashboard` and `/intelligence` in a
   browser. They must render the AdminShell with no console errors.
3. **Dynamic routes** — open `/quiz-bank` and `/sessions`. They must
   render lists from live Supabase (empty is OK; an error banner is not).
4. **Reports panels** — open `/reports`. The three intelligence panels
   (most-missed, facility, treatment) must each render either a table,
   an empty placeholder, or a per-panel error message (not blow up
   the page). See [admin-surfaces.md §5](./admin-surfaces.md).
5. **CSV exports** — click each of the five download links on
   `/reports`. Files must download with `text/csv; charset=utf-8`,
   open cleanly in Excel (BOM intact), and contain only the requested
   filters.
6. **Functions** — `curl` the function endpoints with the right gate
   header. Expect 200s and JSON bodies, not 404s.

Document any failures inline in the deploy ticket with HTTP status,
endpoint, and Netlify deploy ID.

---

## 5. Content seed + mock session

Once verification §4 is green:
1. Apply [supabase/seed/pilot_seed.sql](../supabase/seed/pilot_seed.sql)
   to the live project (SQL editor, idempotent block).
2. Create 1–2 fresh quizzes via `/quiz-bank/new` to validate the write
   path end-to-end. Each must contain ≥1 question with exactly 4
   options (pilot constraint).
3. Create a mock session via `/sessions` → copy the join code and QR.
4. On a phone, open `${MEDRASH_APP_PUBLIC_BASE_URL}/session/{code}`,
   join with a test nickname, submit at least one answer, and confirm
   the leaderboard + `/reports` reflect the activity within ~5 s.

---

## 6. Out of scope for Phase 5

- §6.2 admin auth gate (still open — admin app must not advertise its
  URL publicly until shipped).
- Scheduled / signed-URL exports.
- Excel-native `.xlsx` output.
- Auto-applied migrations via CI.

These get sequenced after the pilot is observed running.
