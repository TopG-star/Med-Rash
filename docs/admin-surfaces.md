# Admin Surfaces — Foundation Spec

Status: **Living document.** Last updated 2026-05-26.

This spec defines the contract, data flow, and security model for all three
admin surfaces (Quiz Bank, Sessions, Reports) so future work plugs in
without re-debating shape.

---

## 1. Architecture summary

The admin app is a **Next.js 16 (App Router)** project (`admin/`). All data
access is server-side:

- **Reads** — async **Server Components** call Supabase directly using the
  service-role key (held only on the server). No data-fetch goes through the
  Flutter-facing Netlify functions.
- **Writes** — **Server Actions** (`"use server"`) mutate via the same
  server-only Supabase client. Form components are Client Components that
  invoke the actions.
- **Auth** — see §6. Supabase session auth is enforced in middleware and route-level
  guards. Middleware redirects unauthenticated traffic to `/login`, and
  Server Components / Server Actions call `requireAdminSession` or
  `requireOwner` to enforce active allow-list membership in `app.admin_users`.

Why not reuse the Netlify functions in `admin/netlify/functions/`?

- Those functions are the **participant gate** for the Flutter app. They
  enforce a participant-facing auth model (`Authorization: Bearer` device
  token minted via Cloudflare Turnstile on `/device-token`, Slice A2) and
  the request shape is participant-centric (identity payload, ranked
  eligibility, etc.).
- Admin needs a **different auth model** and richer queries (joins,
  pagination, aggregates). Server Components + Server Actions are the
  idiomatic Next.js path and avoid an unnecessary HTTP hop.

---

## 2. Shared modules

| Module | Path | Purpose |
| --- | --- | --- |
| Server Supabase client | `admin/src/lib/supabase-server.ts` | Lazy-singleton service-role client. Never import from a Client Component. |
| Admin auth/session guard | `admin/src/lib/admin-session.ts` | Canonical session resolver + role guard helpers (`getAdminSession`, `requireAdminSession`, `requireOwner`). |
| Result helpers | `admin/src/lib/result.ts` (TBD) | Discriminated-union response shape for server actions: `{ ok: true, data } | { ok: false, code, message }`. |

---

## 3. Surface 1 — Quiz Bank

### 3.1 Page route
`admin/src/app/quiz-bank/page.tsx` (list) — implemented.

Future:
- `admin/src/app/quiz-bank/new/page.tsx` — create quiz.
- `admin/src/app/quiz-bank/[slug]/page.tsx` — edit quiz + manage questions.

### 3.2 Data shapes

```ts
type AdminQuizSummary = {
  id: string;             // uuid
  slug: string;           // public identifier used by Flutter
  title: string;
  category: string;
  product: string;        // e.g. 'clexane', 'pradaxa'
  summary: string;
  questionCount: number;  // count(*) from app.questions
  questionCountDefault: number; // app.quizzes.question_count_default
  isActive: boolean;
  updatedAt: string;      // ISO
};

type AdminQuestion = {
  id: string;
  quizId: string;
  position: number;
  prompt: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  tags: string[];
  clinicalArea: string | null;
};
```

### 3.3 Server reads
- `listAdminQuizzes()` — joins `app.quizzes` left-join `count(app.questions)`,
  ordered by `updated_at desc`. Returns `AdminQuizSummary[]`.
- `getAdminQuizDetailBySlug(slug)` — returns one quiz + all questions
  (active + inactive) ordered by position. Source for `/quiz-bank/[slug]`.

### 3.4 Writes (implemented)
- **Canonical lib** `admin/src/lib/quiz-write.ts` —
  `createQuizRecord`, `updateQuizRecord`, `deactivateQuizRecord` (soft
  delete via `is_active=false`), `createQuestionRecord` (auto-positions
  to end if `position` not provided), `updateQuestionRecord`,
  `deactivateQuestionRecord`. Validates slug shape, exactly 4 options
  (pilot), `correct_index` in 0..3, non-empty explanation, tag
  normalization (lowercase, dedup, ≤48 chars each).
- **Server Actions** `admin/src/app/quiz-bank/actions.ts` — used by the
  in-app forms; revalidate `/quiz-bank` and `/quiz-bank/{slug}`.
- **Netlify Function** `POST /.netlify/functions/quiz-bank-write` —
  shared-secret gated via `MEDRASH_ADMIN_WRITE_KEY` header
  `x-medrash-admin-write-key`. Body shape:
  `{ op: 'create_quiz'|'update_quiz'|'deactivate_quiz'|'create_question'|'update_question'|'deactivate_question', payload?: {...}, id?: string }`.

### 3.5 Validation contract
- Slug: `^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$` (1..64 chars, lowercase)
- Title: trimmed, ≤160 chars
- Product: optional free text ≤80 chars (no enum yet)
- Question options: **exactly 4** for pilot (`PILOT_QUESTION_OPTION_COUNT`
  in `admin/src/lib/quiz-bank-types.ts`), each trimmed, non-empty, unique
  case-insensitively, ≤400 chars
- Explanation: required, ≤1200 chars (consumed by Flutter end-of-game
  review and the planned "intelligent reveal after repeated misses" flow)
- Tags: free-form string array, lowercased + deduped, each ≤48 chars
  (suggested chips: `guideline`, `product`)

### 3.6 Deletion policy
- **Soft delete only.** Both `deactivateQuizRecord` and
  `deactivateQuestionRecord` flip `is_active=false`. Historical
  `app.attempts` + `app.answers` rows that reference the row continue to
  resolve, so analytics (most-missed, KPI exports) remain accurate.
- A future commit may add a hard-delete admin op gated by an explicit
  "no historical references" precondition.

### 3.7 Required env vars
- `MEDRASH_ADMIN_WRITE_KEY` — shared secret used by both the
  `session-create` and `quiz-bank-write` Netlify endpoints. Required only
  when those endpoints are exposed; the in-app server actions are reached
  through the admin app's own deployment-gate.

### 3.8 Risks / future hooks
- **CSV bulk upload** ships in §3.9 (Phase 4c).
- **Versioning** — when a question is edited mid-session, attempts.answers
  rows already reference the old prompt; the soft-delete + immutable
  `created_at` model preserves the trail, but the UI should warn before
  editing a quiz that has live sessions.
- **Reorder** is not yet a single transaction; for now position is
  manually editable per-question via the update op.

### 3.9 CSV bulk import (Phase 4c)

- **UI:** `CsvImportPanel` mounted on `/quiz-bank/[slug]`. Browser parses
  the CSV with `papaparse` (dynamic-imported to keep it out of the initial
  route bundle), shows a preview of valid drafts + a per-row error list,
  and only commits on the **Import N Questions** button press.
- **Validator:** `admin/src/lib/quiz-csv.ts` (client-safe — no
  `server-only` deps so the panel can reuse it). `parseCsvQuestionRows`
  emits `{ drafts, errors }` with one `CsvRowError` per offending source
  row.
- **Server commit:** `importQuestionsAction(quizId, quizSlug, drafts)` →
  `bulkCreateQuestions(quizId, inputs)` in `quiz-write.ts`. Quiz existence
  is verified once; positions auto-assign sequentially from
  `nextQuestionPosition` (skipped on per-row failure so the next row
  reuses the slot). Per-row failures are returned as
  `{ index, message }[]` so partial imports tell the admin exactly which
  drafts didn't land.
- **Netlify op:** `POST /.netlify/functions/quiz-bank-write` with
  `{ op: "bulk_create_questions", payload: { quizId, rows: CsvRowInput[] } }`.
  The function re-runs `parseCsvQuestionRows` server-side so external
  callers can't bypass validation; response is
  `{ ok, createdCount, failures, rowErrors }`.
- **CSV format:**
  - Required columns: `prompt, option_1, option_2, option_3, option_4,
    correct_index, explanation`.
  - Optional columns: `clinical_area, tags, position, is_active`.
  - `correct_index` is **1-based** (1..4) for human friendliness; the
    validator converts to the DB's 0-based index.
  - `tags` cell is pipe-separated, e.g. `guideline|product`.
  - `is_active` accepts `true/false/1/0/yes/no/y/n/active/inactive`,
    defaults to `true`.
- **Cap:** 500 rows per call (matches `bulkCreateQuestions` guardrail).

---

## 4. Surface 2 — Sessions

### 4.1 Page route
`admin/src/app/sessions/page.tsx` — list + create form **implemented**.

### 4.2 Data shapes

```ts
type AdminSessionRow = {
  id: string;
  joinCode: string;       // 6-char unambiguous (excludes 0/O/1/I/L)
  name: string;
  hostName: string | null;
  quizId: string;
  quizTitle: string | null;
  startsAt: string | null;
  endsAt: string | null;
  isActiveNow: boolean;          // computed from clock vs [starts_at, ends_at]
  attemptCount: number;
  createdAt: string;
};
```

### 4.3 Server reads (implemented)
- `listAdminSessions()` — `admin/src/lib/session-queries.ts`. Newest first,
  limit 50, joins `quizzes(title)` and `attempts(id)` for counts, computes
  `isActiveNow` server-side.
- `listActiveQuizOptions()` — drop-down source for the create form.

### 4.4 Writes (implemented)
- **Server Action** `createSessionAction` (`admin/src/app/sessions/actions.ts`)
  — used by the in-app form; delegates to `createSessionRecord` and
  `revalidatePath('/sessions')`.
- **Netlify Function** `POST /.netlify/functions/session-create` — same
  canonical logic, gated by `MEDRASH_ADMIN_WRITE_KEY` via header
  `x-medrash-admin-write-key`. For scripted/external admin use.
- Both paths call `createSessionRecord` in `admin/src/lib/session-create.ts`:
  validates quiz exists + is_active, generates 6-char join code from
  alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, retries up to 8× on PG
  unique-violation (`23505`), inserts into `app.sessions`, returns
  `{ session, joinUrl }`.

### 4.5 QR generation (implemented)
- Canonical payload: HTTPS web link `${MEDRASH_APP_PUBLIC_BASE_URL}/session/{joinCode}`
  (matches Flutter route in `app/lib/core/routing/user_router.dart`).
- Rendered **client-side** via dynamic `import('qrcode')` →
  `toDataURL(joinUrl, { margin: 1, width: 220 })` inside the create form's
  success state.

### 4.6 Required env vars
- `MEDRASH_ADMIN_WRITE_KEY` — shared secret for admin-write Netlify
  endpoints (required for `session-create`; future writes will reuse).
- `MEDRASH_APP_PUBLIC_BASE_URL` — origin used to compose join URLs; must
  resolve to the participant entry point.

### 4.7 Risks / future hooks
- `endSession(id)` and `exportSessionData(id, format)` are still TODO.
- Cohort-level filtering (facility, specialty) belongs to a future
  analytics panel layered on top of `app.facility_performance()`.

---

## 5. Surface 3 — Reports

### 5.1 Page route
`admin/src/app/reports/page.tsx` — **implemented (Phase 4d).** Server
component that renders three intelligence panels (Most-Missed, Facility
Performance, Treatment Perception) plus a filter form and five CSV
download buttons.

### 5.2 Data shapes

```ts
// All filters are URL search-params on /reports and pass-through to
// /reports/export/[type]?{...filters}.
type ReportFilters = {
  startsAt?: string | null;   // ISO datetime, lower bound on attempts.started_at
  endsAt?: string | null;     // ISO datetime, upper bound (inclusive)
  quizId?: string | null;     // app.quizzes.id
  sessionId?: string | null;  // app.sessions.id
  facility?: string | null;   // exact-match on app.users.facility
  specialty?: string | null;  // exact-match on app.users.specialty
};
```

### 5.3 Server reads
All in `admin/src/lib/reports-queries.ts` (server-only):
- `getMostMissed(limit, {specialty, facility, sessionId})` → RPC
  `app.knowledge_gaps(limit_count, specialty_filter, facility_filter,
  session_filter)`.
- `getFacilityPerformance(limit)` → RPC `app.facility_performance(limit_count)`.
- `getTreatmentPerception(limit)` → RPC `app.treatment_perception_trends(limit_count)`.
- `getAttemptsExport(filters, limit)` — direct join over
  `attempts → users + quizzes + sessions` with date / quiz / session
  filters; default cap 5 000, hard ceiling 50 000 enforced by the route
  handler.
- `getAnswersExport(filters, limit)` — direct join over
  `answers → attempts!inner → users + quizzes + sessions, questions`
  (inner join on `attempts` so date filters actually constrain); default
  cap 10 000, hard ceiling 100 000.

### 5.4 CSV download contract
- **Route:** `GET /reports/export/{type}?{filters}&limit={n}`
- **Types:** `attempts | answers | most-missed | facility-performance | treatment-perception`
- **Encoding:** UTF-8 with BOM (Excel-friendly), CRLF line terminator,
  RFC 4180 quoting (`admin/src/lib/csv-export.ts`).
- **Filename:** `medrash-{type}-{iso-timestamp}.csv` (sanitized to safe
  ASCII via `csvFilenameSegment`).
- **Headers:** `Content-Type: text/csv; charset=utf-8`,
  `Content-Disposition: attachment`, `Cache-Control: no-store`.
- **Error response:** JSON `{ ok: false, message }` with status 404
  (unknown type) or 500 (Supabase/runtime error).

### 5.5 Risks / future hooks
- **PII:** attempts + answers exports include `users.full_name`,
  `nickname`, `facility`, `specialty`, `profession` for stakeholder
  reporting. Keep access owner-gated and avoid exposing export routes outside
  the authenticated admin portal.
- **Memory:** current exports load the full result set into memory before
  CSV-serializing. Cap (50 000 attempts / 100 000 answers) keeps this
  bounded for the pilot; switch to streaming once we exceed it.
- **PDF / XLSX:** out of scope for Phase 4d; CSV covers stakeholder needs
  and analyst pipelines. Revisit if a stakeholder asks.

---

## 6. Security model

### 6.1 Current production model
- Middleware (`admin/src/middleware.ts`) refreshes/checks Supabase auth
  session cookies and redirects unauthenticated requests to
  `/login?next=<path>`.
- Route-level guards (`requireAdminSession` / `requireOwner`) enforce
  allow-list membership and role restrictions from `app.admin_users`.
- Service-role key remains server-only (`SUPABASE_SERVICE_ROLE_KEY`) and is
  never bundled client-side.

### 6.2 Operational guardrails
- Keep owner-only routes owner-only at the server boundary, not just hidden in
  nav links.
- Keep export endpoints scoped to authenticated admin sessions.
- Keep participant-facing Netlify gate endpoints and admin server-side flows
  separated (no shared auth assumptions).

### 6.3 Env var contract

| Var | Required by | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | server | Required by service-role and SSR clients. |
| `SUPABASE_ANON_KEY` | server/middleware | Used by SSR + middleware Supabase clients. |
| `SUPABASE_SERVICE_ROLE_KEY` | server | **NEVER** expose to client bundle. |
| `MEDRASH_APP_PUBLIC_BASE_URL` | server | Base URL used to generate participant join links for sessions. |
| `MEDRASH_ADMIN_PORTAL_BASE_URL` | server | Preferred base for auth callback/invite redirect URLs. |
| `NEXT_PUBLIC_SITE_URL` | server fallback | Fallback origin when `MEDRASH_ADMIN_PORTAL_BASE_URL` is unset. |
| `MEDRASH_ADMIN_WRITE_KEY` | netlify functions | Shared secret for `session-create` / `quiz-bank-write` admin-write endpoints. |
| `MEDRASH_DEVICE_TOKEN_SECRET` | netlify functions | **Required.** ≥32-char random string. HMAC-SHA256 key for the per-device bearer tokens minted at `POST /device-token` and verified by every participant-facing endpoint (Slice A2). Rotation = generate a new secret, update the Netlify env, redeploy. All in-flight tokens immediately fail `DEVICE_TOKEN_BAD_SIGNATURE`; Flutter clients re-mint on the next request. **Do not rotate during a live pilot session** — the next request from every participant will see one 401 and re-mint, which is fine, but it's still avoidable noise. |
| `MEDRASH_GATE_API_KEY` | **removed (Phase 3c)** | Previously the static shared bearer for `/device-token` bootstrap. After Phase 3c (2026-05-28), the gate-key code path is gone (`_shared/gate.ts` deleted, `_gateApiKey` removed from Flutter). The env var is no longer read anywhere. **Delete this entry from the Netlify env after the Phase 3c deploy lands.** |
| `MEDRASH_GATE_KEY_FALLBACK` | **removed (Phase 3a)** | Previously gated the gate-key fallback in `participant-auth.ts`. The fallback code path is gone; this env var is now ignored. Safe to delete from the Netlify env. |
| `MEDRASH_TURNSTILE_SECRET` | netlify functions | **Required (Phase 3c+).** Cloudflare Turnstile **secret** key (from the Cloudflare dashboard — the longer of the two strings, never expose client-side). Verified by `_shared/turnstile.ts` against `https://challenges.cloudflare.com/turnstile/v0/siteverify` for every `/device-token` request. If unset, the endpoint returns 401 `missing-input-secret` and every mint fails. |
| `MEDRASH_TURNSTILE_SITE_KEY` (`--dart-define`) | flutter web build | **Required (Phase 3c+).** Cloudflare Turnstile **site** key (public, bound to your domain in the Cloudflare dashboard). Passed at Flutter build time via `--dart-define=MEDRASH_TURNSTILE_SITE_KEY=…`; baked into the JS shim in `web/index.html` at runtime. When empty, the Flutter side never fetches a Turnstile token and `/device-token` rejects with 400 `BAD_REQUEST`. `app/scripts/build-web.sh` hard-requires this value via a `:?` shell check. |
| `MEDRASH_TURNSTILE_BYPASS_TOKEN` | netlify functions | **Optional, smoke-tests only.** When set AND a request sends exactly this value as its `turnstileToken`, verification short-circuits to OK. Lets `curl` smoke-tests verify the mint endpoint without solving a real Turnstile challenge. **Never set this in production** — anyone holding the value gets unlimited mints. |
| `MEDRASH_DEVICE_TOKEN_RATE_BURST` | netlify functions | Optional. Max tokens in the per-(IP, device) bucket on `/device-token`. Default 5. |
| `MEDRASH_DEVICE_TOKEN_RATE_REFILL_PER_MIN` | netlify functions | Optional. Tokens added to the bucket per minute. Default 10 (= 1 every 6s). |
| `MEDRASH_DEVICE_TOKEN_RATE_DISABLED` | netlify functions | Optional kill-switch. Set to `true` / `1` to bypass the bucket entirely (smoke tests, perf benchmarks). |

### 6.4 Device-token rotation procedure (Slice A2)

The `MEDRASH_DEVICE_TOKEN_SECRET` env var is the only secret that needs a documented rotation playbook beyond "regenerate and redeploy". Tokens are HMAC-signed, not encrypted, so rotation does not require client coordination — clients self-recover by re-minting on the first 401.

1. **Generate a new secret** of ≥32 chars (e.g. `openssl rand -base64 48`).
2. **Outside of a live pilot session**, update `MEDRASH_DEVICE_TOKEN_SECRET` in the Netlify environment for the production site.
3. **Trigger a deploy** (or wait for the next one) so the new value reaches every function instance.
4. **Verify** by hitting `POST /.netlify/functions/device-token` with a fresh Turnstile token (or set `MEDRASH_TURNSTILE_BYPASS_TOKEN` temporarily and call with that value) — the response body should include a new `token` whose signature differs from any cached one on a participant device.
5. **No client action is required.** Every existing token will fail with `DEVICE_TOKEN_BAD_SIGNATURE` on its next use; the Flutter `DeviceTokenStore` re-mints on the request after that. Phase 3a removed the legacy gate-key fallback server-side and Phase 3c removed the gate-key bootstrap entirely, so a rotation now produces one hard 401 per device followed by a successful Turnstile-backed re-mint. End-user impact is one extra round-trip per device.
6. **Audit:** there is no rotation log table yet — record the rotation date and reason in the Decisions Log of `docs/security-hardening-plan.md`.

### 6.5 Database RLS posture (Slice A3)

After Slice A3 (migrations `014`–`016`, 2026-05-28), every table in the `app.*` schema has RLS enabled and every view in the schema runs with `security_invoker = true`. Service-role bypasses RLS in all cases; the table below documents what each role can do in addition to that bypass.

| Table / view | RLS | service_role | authenticated | anon |
| --- | --- | --- | --- | --- |
| `app.users` | on | all (via bypass) | — | — |
| `app.user_devices` | on | all (via bypass) | — | — |
| `app.quizzes` | on | all (via bypass) | — | — |
| `app.questions` | on | all (via bypass) | — | — |
| `app.sessions` | on | all (explicit `sessions_service_role_all` + bypass) | — | — (`sessions_public_select` dropped) |
| `app.attempts` | on | all (via bypass) | — | — |
| `app.answers` | on | all (via bypass) | — | — |
| `app.session_join_events` | on | all (via bypass) | — | — |
| `app.admin_users` | on (A3) | all (explicit `admin_users_service_role_all` + bypass) | `select` own row only (`admin_users_self_select`) | — |
| `app.auth_rate_limit` | on | all (via bypass) | — | — |
| `app.ranked_attempt_totals_all_time` | view (`security_invoker=true`, A3) | — | — | — |
| `app.ranked_attempt_totals_monthly` | view (`security_invoker=true`, A3) | — | — | — |

Notes:
- `sessions_public_select` (formerly `using (true)`) was dropped because every TS/Dart caller already goes through service-role functions; deny-by-default is the correct posture until a real anon read use-case appears. The plan's spec called for a narrow `status in ('open','live')` policy, but `app.sessions` has no `status` column (lifecycle is `starts_at`/`ends_at`), so we deviated.
- `admin_users_self_select` is defence-in-depth — no current code path queries `admin_users` under a user session, but if a future SSR route does, an authenticated admin can read only their own row.
- All views in `app.*` should ship with `with (security_invoker = true)` going forward (this becomes a lint check in Block B Slice B6).

---

## 7. Implementation status

1. **Quiz Bank** — complete for pilot scope (list/create/edit/deactivate,
   question management, CSV import).
2. **Sessions** — complete for pilot scope (create/list/QR/join-link actions,
   owner/host scope handling, live view route).
3. **Reports + Intelligence** — complete for pilot scope (filters,
   analytics panels, CSV exports).
4. **Admin Users** — complete for pilot scope (invite, role/status updates,
   reinvite lifecycle).
5. **Shared UI + accessibility hardening** — complete for current rollout
   wave (Vibrant Pulse shared shell + Slice 6 keyboard/screen-reader pass).

Recommended next step: add focused Playwright smoke coverage for the admin
auth/login flow and one owner-only route guard path.
