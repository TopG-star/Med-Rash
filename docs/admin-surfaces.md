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
- `getAdminQuiz(slug)` — returns one quiz + ordered questions.

### 3.4 Server actions (future commit)
- `upsertQuiz(input)` — create or update by slug. Validates slug
  uniqueness, non-empty title, product enum.
- `deleteQuiz(slug)` — soft-delete by setting `is_active=false`. Hard
  delete only if `attempts` and `questions` cascades have run. Add a
  confirmation modal in the UI.
- `upsertQuestion(input)` — create or update. Validates options length ≥ 2,
  `correct_index` within bounds, position auto-increments.
- `reorderQuestions(slug, orderedIds[])` — bulk-update positions in a
  single transaction.
- `deleteQuestion(id)` — hard delete. Block if `app.answers` reference it
  (FK guard).

### 3.5 Validation contract
- Slug: `^[a-z0-9][a-z0-9-]{2,63}$`
- Title: trimmed, 3..160 chars
- Product: one of the values seeded in `003_quiz_product_and_position.sql`
  (extendable via migration)
- Question options: 2..6 items, each trimmed, 1..240 chars

Validation lives in a single `validators.ts` per surface; server actions call
it before any DB write so admin UI and any future API share rules.

### 3.6 Risks / future hooks
- **CSV bulk upload** button is currently a UI stub. Future: a Server Action
  accepts a parsed CSV (papaparse in client), validates rows, opens a
  preview, then commits in a transaction.
- **Versioning** — when a quiz is edited mid-session, the `app.attempts`
  rows already reference the old question IDs. The schema supports this; UI
  should warn before bulk-editing an active quiz.

---

## 4. Surface 2 — Sessions

### 4.1 Page route
`admin/src/app/sessions/page.tsx` — currently UI stub.

### 4.2 Data shapes

```ts
type AdminSession = {
  id: string;
  joinCode: string;       // human-friendly e.g. "KBTH-CME-2026"
  title: string;
  quizSlug: string;
  host: string;
  startsAt: string | null;
  endsAt: string | null;
  isActive: boolean;
  participantsCount: number;     // distinct attempts.user_id
  completionRate: number | null; // 0..1
  shareUrl: string;              // deep link for QR
};
```

### 4.3 Server reads
- `listSessions({ activeOnly?: boolean })` — joins `app.sessions` with
  aggregates from `app.attempts`. Uses the existing `app.session_kpis(uuid)`
  RPC for per-session metrics.
- `getSession(id)` — full session + computed KPIs.

### 4.4 Server actions (future)
- `createSession(input)` — generates `joinCode` (5-char alphanumeric with
  collision retry), sets `is_active=true`, returns `{ id, joinCode,
  shareUrl }`. Share URL is composed from `NEXT_PUBLIC_APP_DEEP_LINK_BASE`.
- `endSession(id)` — sets `is_active=false`; no destructive delete.
- `exportSessionData(id, format: 'csv'|'xlsx')` — streams a download.

### 4.5 QR generation
- QR rendering happens **client-side** from `shareUrl` via `qrcode.react`
  (to be added). Server returns the URL; client renders the bitmap. This
  keeps the server stateless.

### 4.6 Risks / future hooks
- Join-code collisions are rare but possible; the create action must retry
  up to N times with a unique-violation guard, mirroring the pattern in
  `_shared/supabase.ts` (`isUniqueViolation`).
- Cohort-level filtering (facility, specialty) belongs to a future analytics
  panel layered on top of `app.facility_performance()`.

---

## 5. Surface 3 — Reports

### 5.1 Page route
`admin/src/app/reports/page.tsx` — currently UI stub.

### 5.2 Data shapes

```ts
type ReportRequest = {
  dataSets: Array<'attempts'|'answers'|'demographics'>;
  range: { from: string; to: string }; // ISO dates inclusive
  format: 'csv' | 'xlsx';
};

type ReportArtifact = {
  id: string;            // signed download URL bound to a short TTL
  filename: string;
  generatedAt: string;
  sizeBytes: number;
};
```

### 5.3 Server reads
Bound to the analytics queries already shipped in
`supabase/queries/analytics.sql` and the RPCs in migration 002:
- `app.session_kpis(uuid)`
- `app.knowledge_gaps(limit, specialty?, facility?, session?)`
- `app.facility_performance(limit)`
- `app.treatment_perception_trends(limit)`

These power both the on-screen panels and the export pipeline.

### 5.4 Server actions (future)
- `generateReport(req)` — runs each requested dataset query in a worker,
  serializes to CSV/XLSX, stores in Supabase Storage under `reports/`,
  returns a signed URL valid for 24h.
- `listPreviousExports()` — lists from `reports/` bucket, ordered by
  `created_at desc`.

### 5.5 Risks / future hooks
- Large exports must stream — never load full result set into memory.
  Use Supabase Storage resumable uploads.
- PII boundary: `users.full_name` is **excluded** from exports by default.
  Demographics export uses `nickname`, `facility`, `specialty` only.

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
