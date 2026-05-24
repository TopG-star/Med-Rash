# Phase B — Invite Hardening & First-Run Onboarding

**Status:** B1 in progress · B2 pending · B3 pending
**Owner:** Gerald (admin) · **Workspace:** `c:\Users\USER\Desktop\Personal\medRash`

## Context

Phase A shipped Supabase Auth + an `app.admin_users` allowlist + identity-aware
writes (commit `08bf36b` on `origin/main`, verified live on Netlify). During the
post-deploy smoke test we found two issues with the invite path:

1. **Security:** opening an invite link in a browser already signed in as
   another admin shows the existing admin's session, not the invitee's. Root
   cause: `app/auth/callback/route.ts` silently redirects when there is no
   `?code=` and never signs out the existing session before processing a new
   token.
2. **UX:** invitees land directly on `/dashboard` with no profile capture; the
   sidebar shows `geraldamponsah03` (email local-part), not a real name; and
   the invite button stays enabled forever even after acceptance.

## Decisions locked

- **Role model collapses to three tiers** for the whole project:
  - `admin` — the workspace owner (Gerald). Single seat. Was `superadmin`.
  - `host` — invited teammates (rep / manager / team member). Was `admin`.
  - `participants` — mobile app players (unchanged, lives in Flutter app).
  All `owner` / `superadmin` references get migrated to `admin` and all
  existing `admin` rows become `host`.
- **Host onboarding fields**: Full Name (required), Email (required,
  pinned read-only from the invite), Role/Title (optional free-text — e.g.
  "Rep", "Regional Manager", "Team Lead"). No Facility / Specialty
  (different from the Flutter participant onboarding — hosts are internal
  staff, not clinicians).
- **Re-invite rule**: once a host's `accepted_at IS NOT NULL`, the invite
  button disappears for that email and `inviteAdminAction` rejects re-invites
  server-side.

## B1 — Security fix (callback hardening) — IN PROGRESS

### Tasks

- B1.1 Extract callback logic into a pure `handleAuthCallback({ supabase, code })`
  function so it is unit-testable.
- B1.2 Rewrite `GET /auth/callback`:
  - Always call `supabase.auth.signOut()` **before** processing the new code,
    so any prior session cookie is wiped first.
  - If `?code=` present → `exchangeCodeForSession(code)`; on success redirect
    to `next`; on error redirect `/denied?reason=exchange`.
  - If no `?code=` → return an HTML interstitial that reads
    `window.location.hash`. If hash contains `access_token` + `refresh_token`
    it `fetch()`-POSTs them to the same route; otherwise it redirects to
    `/denied?reason=callback_no_code` (no silent dashboard bounce).
- B1.3 Add `POST /auth/callback` accepting `{ access_token, refresh_token,
  next? }`. Signs out, then `setSession({...})`, returns `{ ok: true, next }`.
- B1.4 Vitest case `callback-handler.test.ts` asserting:
  - `signOut` is invoked **before** `exchangeCodeForSession` (order matters —
    if exchange ran first, the new cookies would be overwritten by the
    signOut and the session would be lost).
  - When called with code "invitee-code" while a prior owner session exists,
    the post-handler session reflects the invitee, not the owner.
  - When called with no code, returns `needsHashFlow: true` so the route can
    render the interstitial.
  - When called with an invalid code, returns `{ ok: false, reason: 'exchange' }`
    and the route surfaces `/denied?reason=exchange` (no silent redirect).

### Verification

- `cd admin && npm run typecheck` PASS
- `cd admin && npm run lint` PASS
- `cd admin && npm run test` PASS (existing 9 + new callback tests)
- `cd admin && npm run build` PASS
- Live smoke (after deploy): owner signed in → open invite link from another
  email in same browser → land on `/login` or `/accept-invite` as invitee,
  **not** owner's dashboard.

## B2 — Onboarding (schema 007 + /accept-invite) — PENDING

### Tasks

- B2.1 Migration `007_admin_onboarding.sql`:
  - `alter table app.admin_users`
    - `rename column role check` to collapse to `('admin','host')`
    - migrate data: `update admin_users set role='admin' where role='superadmin'`
      then `update admin_users set role='host' where role='admin' and user_id <> '<owner-uuid>'`
      (sequenced safely)
    - `add column full_name text`
    - `add column role_title text`  -- the optional free-text label
    - `add column portfolio_url text`
    - `add column accepted_at timestamptz`
- B2.2 New route `/accept-invite`:
  - Server guard: `requireAdminSession()` then if `accepted_at IS NULL`
    render form; else redirect `/dashboard`.
  - Client form fields: Full Name (required), Email (read-only, pre-filled),
    Role/Title (optional), styled per `design UI context/UI 2/code.html`
    neo-brutalist pattern (border-3, shadow-[0_4px_0_0_rgba(27,27,27,1)],
    active:translate-y-1).
  - Server action `acceptInvitationAction` updates the three columns +
    `accepted_at = now()` then `revalidatePath('/dashboard')` and redirect.
- B2.3 Update `requireAdminSession()` to also fetch `accepted_at` and
  redirect to `/accept-invite` (except when already on that path) when null.
- B2.4 Update `admin-users-queries.ts` `AdminUserRow` to include `fullName`,
  `roleTitle`, `acceptedAt`.
- B2.5 Sidebar / AdminShell uses `fullName ?? email.split('@')[0]`.

## B3 — Invite surface polish — PENDING

### Tasks

- B3.1 `/admin-users` table adds **Status** column: `Pending` (no
  `acceptedAt`) or `Joined <date>`.
- B3.2 Row actions:
  - Pending row → "Resend invite" button (re-generates the link).
  - Joined row → no invite button; only Role change + Deactivate.
- B3.3 `inviteAdminAction` server guard: if a row exists with
  `accepted_at IS NOT NULL` for that email, return
  `{ ok: false, message: '<email> has already joined; revoke and re-add if needed.' }`.
- B3.4 Vitest case for the re-invite rejection.

## Phasing & deploy

Each phase ships as its own commit so we can roll back independently:

1. **B1 commit** → push → verify live invite security fix.
2. **B2 commit** (migration 007 applied via Supabase SQL Editor first, then
   code) → push → verify host can onboard.
3. **B3 commit** → push → verify Pending/Joined UI + re-invite block.
