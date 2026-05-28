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
   - [supabase/migrations/006_admin_auth.sql](../supabase/migrations/006_admin_auth.sql) — installs `app.admin_users` allowlist + `created_by` columns on quizzes/sessions/questions.
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
| `SUPABASE_ANON_KEY` | admin SSR + functions | Used to read the caller's Supabase session (cookie-bound on SSR; Bearer-bound on functions). |
| `MEDRASH_TURNSTILE_SECRET` | functions only | Cloudflare Turnstile secret key. Required by `/device-token` to verify the bootstrap challenge (Slice A2 phase 3c). |
| `MEDRASH_TURNSTILE_SITE_KEY` | flutter web build | Cloudflare Turnstile site key (public, domain-bound). Required at Flutter web build time via `--dart-define`. |
| `MEDRASH_ADMIN_WRITE_KEY` | functions only | **Optional defense-in-depth** shared secret. When set, admin-write functions require both `x-medrash-admin-write-key` AND a valid Supabase admin session. Leave empty to disable. |
| `MEDRASH_INTERNAL_BYPASS` | functions only | **Secret.** Server-to-server bypass header for scheduled jobs. Senders pass `x-medrash-internal-bypass: <value>`. Leave UNSET in production unless a scheduled job needs it. |
| `MEDRASH_ADMIN_PORTAL_BASE_URL` | admin SSR | Public origin of the admin app itself. Used to build the magic-link `emailRedirectTo` and the invitation redirect. Falls back to `NEXT_PUBLIC_SITE_URL`. |
| `ADMIN_BOOTSTRAP_EMAIL` | seed script only | Email of the first superadmin. Consumed once by `admin/scripts/seed-admin.mjs`. |
| `MEDRASH_APP_PUBLIC_BASE_URL` | admin SSR | Origin used to build session join URLs / QR codes. Set to the Flutter app's public origin (not the admin origin). |

Recommended secret hygiene:
- Generate `MEDRASH_INTERNAL_BYPASS` with `openssl rand -hex 32`. If `MEDRASH_ADMIN_WRITE_KEY` is set, generate it the same way. `MEDRASH_TURNSTILE_SECRET` is issued by the Cloudflare Turnstile dashboard, not generated locally.
- Mark `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, and all `MEDRASH_*_KEY` / `MEDRASH_INTERNAL_BYPASS` values as
  **Sensitive** in Netlify so they are not logged in deploy output.

### 2.1 Bootstrap the first superadmin (one-time)

After migration 006 is applied and `SUPABASE_ANON_KEY` is set, seed the
first admin from your local machine:

```pwsh
$env:SUPABASE_URL = "https://<ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "<service role>"
$env:ADMIN_BOOTSTRAP_EMAIL = "founder@medrash.example"
cd admin
node ./scripts/seed-admin.mjs
cd ..
Remove-Item Env:SUPABASE_URL, Env:SUPABASE_SERVICE_ROLE_KEY, Env:ADMIN_BOOTSTRAP_EMAIL
```

> The script must run from `admin/` so Node resolves `@supabase/supabase-js`
> from `admin/node_modules`.

The script invites the user via Supabase's email provider and upserts
an `app.admin_users` row with `role = 'superadmin'` and
`is_active = true`. From then on, every additional admin is invited
from `/admin-users` inside the admin app — no scripts required.

---

## 3. Local smoke test (before redeploying)

From the workspace root, run hosted-check against the live Supabase
project. This validates that the `app` schema is reachable with the
service-role key and all 7 required tables respond.

```pwsh
$env:SUPABASE_URL = "https://<ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "<paste service role here>"
# Optional — when set, also smoke the participant SPA + functions origin:
$env:MEDRASH_APP_PUBLIC_BASE_URL = "https://<participant-site>.netlify.app"
$env:MEDRASH_FUNCTIONS_BASE_URL  = "https://<admin-site>.netlify.app/.netlify/functions"
node ./scripts/hosted-check.mjs
```

Expected output: `Connectivity check passed` followed by `Table 'X'
reachable` for users, quizzes, questions, sessions, attempts, answers,
session_join_events. When the two optional URLs are set, the script
also asserts `/` and `/session/SMOKE` return the Flutter shell (proving
the SPA fallback is wired) and that `/.netlify/functions/health`
returns 200. Any failure aborts the deploy plan.

After the run:
```pwsh
Remove-Item Env:SUPABASE_URL
Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY
Remove-Item Env:MEDRASH_APP_PUBLIC_BASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:MEDRASH_FUNCTIONS_BASE_URL  -ErrorAction SilentlyContinue
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

- ~~§6.2 admin auth gate~~ — shipped in Phase A (migration 006 + Supabase Auth magic-link).
- Scheduled / signed-URL exports.
- Excel-native `.xlsx` output.
- Auto-applied migrations via CI.

These get sequenced after the pilot is observed running.
