# Admin Surfaces — Foundation Spec

Status: **Living document.** Last updated 2026-05-18.

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
- **Auth** — see §5. For pilot, admin app must be deployed behind a Netlify
  Identity / Basic Auth / single-secret cookie gate before being made
  internet-reachable. Right now the app is **unauthenticated** (acceptable
  only for local dev or a private preview deploy).

Why not reuse the Netlify functions in `admin/netlify/functions/`?

- Those functions are the **participant gate** for the Flutter app. They
  enforce a participant-facing auth model (`MEDRASH_GATE_API_KEY`) and the
  request shape is participant-centric (identity payload, ranked
  eligibility, etc.).
- Admin needs a **different auth model** and richer queries (joins,
  pagination, aggregates). Server Components + Server Actions are the
  idiomatic Next.js path and avoid an unnecessary HTTP hop.

---

## 2. Shared modules

| Module | Path | Purpose |
| --- | --- | --- |
| Server Supabase client | `admin/src/lib/supabase-server.ts` | Lazy-singleton service-role client. Never import from a Client Component. |
| Admin auth gate (TODO) | `admin/src/lib/admin-auth.ts` | Single entry-point for every page/server-action to require admin session. Currently a TODO stub. |
| Result helpers | `admin/src/lib/result.ts` (TBD) | Discriminated-union response shape for server actions: `{ ok: true, data } | { ok: false, code, message }`. |

---

## 3. Surface 1 — Quiz Bank

### 3.1 Page route
`admin/src/app/quiz-bank/page.tsx` (list) — implemented in this commit.

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
  reporting. Surface 3 must sit behind §6.2's auth gate before any
  internet-exposed deploy.
- **Memory:** current exports load the full result set into memory before
  CSV-serializing. Cap (50 000 attempts / 100 000 answers) keeps this
  bounded for the pilot; switch to streaming once we exceed it.
- **PDF / XLSX:** out of scope for Phase 4d; CSV covers stakeholder needs
  and analyst pipelines. Revisit if a stakeholder asks.

---

## 6. Security model

### 6.1 Today (pilot scaffolding)
- Admin app is **unauthenticated**. Acceptable only for local dev and
  private preview deploys. Do not point a production DNS at it without §6.2.
- Service-role key is held in `SUPABASE_SERVICE_ROLE_KEY` and used only by
  Server Components / Server Actions. Never imported from a Client
  Component.

### 6.2 Before any internet-exposed deploy (blocker)
Pick one and ship it before exposing the admin app:
- **Netlify Identity / Basic Auth** at the edge.
- **Single-secret cookie gate** — admin enters a shared password once,
  signed cookie via `iron-session`, every page + server action calls
  `requireAdminSession()`.
- **Supabase Auth (preferred long-term)** — magic-link or OAuth, with an
  `app.admin_users` allow-list table.

The chosen gate lives behind `admin/src/lib/admin-auth.ts` so the rest of
the codebase doesn't change when we upgrade the model.

### 6.3 Env var contract

| Var | Required by | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | server | Public-safe but only injected server-side here. |
| `SUPABASE_SERVICE_ROLE_KEY` | server | **NEVER** expose to client bundle. |
| `MEDRASH_ADMIN_SESSION_SECRET` | server (future) | 32-byte secret for iron-session cookies. |
| `NEXT_PUBLIC_APP_DEEP_LINK_BASE` | client | Used to build session shareUrl. |

---

## 7. Implementation order (recommended)

1. **Quiz Bank** — list, then create/edit, then delete. List shipped in
   this commit. Mutation flows in follow-up commits.
2. **Sessions** — create + join-code + QR, then list with KPIs, then
   export.
3. **Reports** — wire the four analytics RPCs to on-screen panels first,
   then add the export pipeline.

Each surface should ship behind a small smoke test (Playwright or
component-level) before its commits merge.
