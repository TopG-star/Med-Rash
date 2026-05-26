# MedRash Admin Portal

Next.js 16 admin portal for MedRash pilot operations (quiz bank, sessions,
reports, intelligence, and admin-user management).

## Local Setup

1. Install dependencies:

```bash
npm install
```

2. Configure environment variables in `.env.local`:

```bash
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
MEDRASH_APP_PUBLIC_BASE_URL=
MEDRASH_ADMIN_PORTAL_BASE_URL=
NEXT_PUBLIC_SITE_URL=
MEDRASH_ADMIN_WRITE_KEY=
```

Notes:
- `MEDRASH_ADMIN_PORTAL_BASE_URL` is preferred for auth callback and invite redirects.
- `NEXT_PUBLIC_SITE_URL` is used as a fallback when `MEDRASH_ADMIN_PORTAL_BASE_URL` is unset.
- `MEDRASH_ADMIN_WRITE_KEY` is required for Netlify function admin-write endpoints.

3. Start dev server:

```bash
npm run dev
```

## Auth Model

- `src/middleware.ts` validates Supabase session cookies and redirects unauthenticated users to `/login`.
- Route-level guards in `src/lib/admin-session.ts` enforce active allow-list membership in `app.admin_users`.
- Owner-only surfaces call `requireOwner` server-side.

## Verification Commands

Run these before merge/deploy:

```bash
npm run lint
npm run typecheck
npm run test
```

For focused route work, run scoped ESLint on touched files in addition to the full checks.

## Guardrails

- Never import `src/lib/supabase-server.ts` from client components.
- Keep service-role operations server-side only.
- Keep participant Netlify gate flows separate from admin auth/session flows.
