# Phase A — Admin Auth Gate Implementation Plan

**Goal:** Replace the single shared-secret `MEDRASH_ADMIN_PORTAL_KEY` Basic-Auth shim with real Supabase Auth (magic link), an `admin_users` allowlist with `admin` / `superadmin` roles, identity-aware writes, and a default-mine/all visibility toggle — without rewriting the existing admin pages or Netlify functions.

**Architecture:** Next.js admin (Netlify SSR) uses `@supabase/ssr` to read the rep's session from cookies in middleware and server actions. A new `admin_users` table cross-checks every request (`is_active = true`). Admin-write Netlify functions verify both the existing shared secret **and** the rep's JWT via `supabase.auth.getUser(jwt)`, then cross-check the allowlist. `created_by` is set from the verified subject on every insert — never trusted from the request body. Pre-auth rows keep `created_by = NULL` and render as `Pre-auth seed`.

**Tech Stack:** Next.js 16 + React 19, `@supabase/ssr` (NEW), `@supabase/supabase-js` 2.49, vitest (NEW, admin-only), Supabase Postgres + Auth, Netlify Functions v2 (Node 22), Resend SMTP.

**Sub-phases:**
- **A0** — Schema migration + bootstrap script + vitest infra.
- **A1** — Sign-in flow + middleware + login/denied/callback pages.
- **A2** — `/admin-users` page + default-mine toggle + `created_by` plumbing in server actions.
- **A3** — Defense-in-depth on Netlify write functions (JWT + allowlist).
- **A4** *(post-launch, not in this plan)* — OTP offline fallback, true global sign-out, remember-me.

**Files to create:**
- `supabase/migrations/006_admin_auth.sql`
- `scripts/seed-admin.mjs`
- `admin/vitest.config.ts`
- `admin/src/lib/supabase-ssr.ts`
- `admin/src/lib/admin-session.ts`
- `admin/src/lib/created-by.ts`
- `admin/src/lib/admin-users-queries.ts`
- `admin/src/app/login/page.tsx`
- `admin/src/app/login/login-form.tsx`
- `admin/src/app/login/actions.ts`
- `admin/src/app/auth/callback/route.ts`
- `admin/src/app/auth/signout/route.ts`
- `admin/src/app/denied/page.tsx`
- `admin/src/app/admin-users/page.tsx`
- `admin/src/app/admin-users/invite-form.tsx`
- `admin/src/app/admin-users/admin-row-actions.tsx`
- `admin/src/app/admin-users/actions.ts`
- `admin/src/components/admin-user-menu.tsx`
- `admin/src/components/scope-toggle.tsx`
- `admin/netlify/functions/_shared/admin-user-session.ts`
- `admin/netlify/functions/_shared/admin-user-session.test.ts`

**Files to modify:**
- `admin/package.json`
- `admin/src/middleware.ts`
- `admin/src/lib/supabase-server.ts`
- `admin/src/lib/design-tokens.ts`
- `admin/src/lib/session-create.ts`
- `admin/src/lib/session-queries.ts`
- `admin/src/lib/quiz-bank-queries.ts`
- `admin/src/lib/quiz-write.ts`
- `admin/src/components/admin-shell.tsx`
- `admin/src/components/admin-sidebar.tsx`
- `admin/src/app/dashboard/page.tsx`
- `admin/src/app/sessions/page.tsx`
- `admin/src/app/sessions/actions.ts`
- `admin/src/app/quiz-bank/page.tsx`
- `admin/src/app/quiz-bank/actions.ts`
- `admin/src/app/reports/page.tsx`
- `admin/src/app/intelligence/page.tsx`
- `admin/netlify/functions/session-create.ts`
- `admin/netlify/functions/quiz-bank-write.ts`
- `admin/netlify/functions/_shared/http.ts`
- `docs/hosted-deploy.md`

---

## A0 — Schema, bootstrap, test infra

### Task A0.1: Add migration `006_admin_auth.sql`

**Files:**
- Create: `supabase/migrations/006_admin_auth.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 006_admin_auth.sql
-- Adds the admin_users allowlist (role + soft-deactivate + invite trail) and
-- attaches created_by attribution to quizzes, sessions, and questions.
-- Pre-auth rows keep created_by = NULL (rendered as "Pre-auth seed" in UI).
-- This migration NEVER writes to auth.users.

begin;

create extension if not exists citext;

-- 1. Allowlist of admins (subset of auth.users)
create table if not exists app.admin_users (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       citext not null unique,
  role        text not null default 'admin'
                check (role in ('admin', 'superadmin')),
  is_active   boolean not null default true,
  invited_by  uuid references app.admin_users(user_id) on delete set null,
  invited_at  timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists admin_users_active_idx
  on app.admin_users(is_active)
  where is_active;

-- 2. created_by attribution. Nullable: NULL = pre-auth seed.
alter table app.quizzes
  add column if not exists created_by uuid references auth.users(id) on delete set null;

alter table app.sessions
  add column if not exists created_by uuid references auth.users(id) on delete set null;

alter table app.questions
  add column if not exists created_by uuid references auth.users(id) on delete set null;

create index if not exists quizzes_created_by_idx   on app.quizzes(created_by);
create index if not exists sessions_created_by_idx  on app.sessions(created_by);
create index if not exists questions_created_by_idx on app.questions(created_by);

commit;
```

- [ ] **Step 2: Run the migration locally (Supabase CLI or psql)**

Run (Supabase CLI):
```bash
supabase db push
```
Or against the live project, paste into the SQL editor.

Expected: `CREATE TABLE`, `CREATE INDEX`, three `ALTER TABLE` succeed; no error on idempotent re-run.

- [ ] **Step 3: Verify schema**

Run in SQL editor:
```sql
select column_name, is_nullable, data_type
from information_schema.columns
where table_schema = 'app'
  and table_name in ('admin_users','quizzes','sessions','questions')
  and column_name in ('user_id','email','role','is_active','invited_by','created_by')
order by table_name, column_name;
```

Expected: `admin_users` has all 6 listed columns; `quizzes`, `sessions`, `questions` each have a nullable `created_by uuid`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/006_admin_auth.sql
git commit -m "feat(db): add admin_users allowlist + created_by columns (migration 006)"
```

---

### Task A0.2: Bootstrap script `scripts/seed-admin.mjs`

**Files:**
- Create: `scripts/seed-admin.mjs`

- [ ] **Step 1: Write the script**

```javascript
#!/usr/bin/env node
// scripts/seed-admin.mjs
//
// Bootstraps the first superadmin (or upgrades an existing admin to
// superadmin) on a fresh Supabase project. Uses the Supabase Admin API,
// not raw SQL on auth.users.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   ADMIN_BOOTSTRAP_EMAIL=you@example.com \
//   node ./scripts/seed-admin.mjs

import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL?.trim();
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const email = process.env.ADMIN_BOOTSTRAP_EMAIL?.trim();

if (!url || !serviceRoleKey) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  process.exit(1);
}
if (!email) {
  console.error("ADMIN_BOOTSTRAP_EMAIL is required.");
  process.exit(1);
}

const supabase = createClient(url, serviceRoleKey, {
  db: { schema: "app" },
  auth: { autoRefreshToken: false, persistSession: false },
});

async function findAuthUserByEmail(targetEmail) {
  // listUsers is paginated; first 1000 is more than enough for pilot.
  const { data, error } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (error) throw new Error(`listUsers failed: ${error.message}`);
  const lower = targetEmail.toLowerCase();
  return data.users.find((u) => (u.email ?? "").toLowerCase() === lower) ?? null;
}

async function main() {
  console.log(`[seed-admin] bootstrap email: ${email}`);

  let authUser = await findAuthUserByEmail(email);
  if (!authUser) {
    console.log("[seed-admin] inviting via auth.admin.inviteUserByEmail …");
    const { data, error } = await supabase.auth.admin.inviteUserByEmail(email);
    if (error) throw new Error(`inviteUserByEmail failed: ${error.message}`);
    authUser = data.user;
  } else {
    console.log(`[seed-admin] auth user already exists (${authUser.id})`);
  }

  const { error: upsertError } = await supabase
    .from("admin_users")
    .upsert(
      {
        user_id: authUser.id,
        email,
        role: "superadmin",
        is_active: true,
        invited_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );

  if (upsertError) {
    throw new Error(`admin_users upsert failed: ${upsertError.message}`);
  }

  console.log("[seed-admin] OK");
  console.log(`  user_id : ${authUser.id}`);
  console.log(`  email   : ${email}`);
  console.log(`  role    : superadmin`);
  console.log(`  active  : true`);
  console.log("");
  console.log("Sign in by visiting /login and requesting a magic link to this address.");
}

main().catch((err) => {
  console.error("[seed-admin] FAILED:", err.message);
  process.exit(2);
});
```

- [ ] **Step 2: Smoke-run the script with placeholder env to confirm it exits cleanly on missing vars**

Run:
```pwsh
node ./scripts/seed-admin.mjs
```
Expected: exits with code 1, message `SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.`

- [ ] **Step 3: Commit**

```bash
git add scripts/seed-admin.mjs
git commit -m "feat(scripts): bootstrap first superadmin via Supabase Admin API"
```

---

### Task A0.3: Add vitest infrastructure to admin

**Files:**
- Modify: `admin/package.json`
- Create: `admin/vitest.config.ts`

- [ ] **Step 1: Add vitest + ssr deps**

Run:
```pwsh
cmd /c "cd admin && npm install --save @supabase/ssr"
cmd /c "cd admin && npm install --save-dev vitest @vitest/coverage-v8"
```

- [ ] **Step 2: Add the `test` script in `admin/package.json`**

Modify the `scripts` block so it reads:
```json
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "eslint",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest"
  },
```

- [ ] **Step 3: Write `admin/vitest.config.ts`**

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: [
      "src/**/*.test.ts",
      "src/**/*.test.tsx",
      "netlify/functions/**/*.test.ts",
    ],
    globals: false,
  },
});
```

- [ ] **Step 4: Run the empty suite to confirm wiring**

Run:
```pwsh
cmd /c "cd admin && npm test"
```
Expected: `No test files found, exiting with code 0` (vitest may print exit code 1 when no tests; if so, ignore — first real test in A3.1 will green this).

- [ ] **Step 5: Commit**

```bash
git add admin/package.json admin/package-lock.json admin/vitest.config.ts
git commit -m "chore(admin): add vitest + @supabase/ssr"
```

---

## A1 — Sign-in flow + middleware + login UI

### Task A1.1: SSR Supabase client helper

**Files:**
- Create: `admin/src/lib/supabase-ssr.ts`

- [ ] **Step 1: Write the helper**

```typescript
import "server-only";

import { cookies } from "next/headers";
import { createServerClient, type CookieOptions } from "@supabase/ssr";

/**
 * Cookie-bound Supabase client for Next.js Server Components and Server Actions.
 * Carries the signed-in rep's session so RLS / auth.uid() resolves correctly.
 * The `app` schema is the canonical MedRash schema.
 *
 * For service-role / system reads, keep using getAdminSupabaseClient() from
 * ./supabase-server.ts.
 */
export async function getSupabaseServerClient() {
  const url = process.env.SUPABASE_URL?.trim();
  const anonKey = process.env.SUPABASE_ANON_KEY?.trim();

  if (!url || !anonKey) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_ANON_KEY must be configured for the admin app.",
    );
  }

  const cookieStore = await cookies();

  return createServerClient(url, anonKey, {
    db: { schema: "app" },
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options as CookieOptions);
          }
        } catch {
          // Called from a Server Component (read-only context). The middleware
          // refreshes the session on every request so a missed write here is
          // safe.
        }
      },
    },
  });
}
```

- [ ] **Step 2: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```
Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add admin/src/lib/supabase-ssr.ts
git commit -m "feat(admin): add cookie-bound SSR Supabase client"
```

---

### Task A1.2: `admin-session.ts` — the allowlist gate

**Files:**
- Create: `admin/src/lib/admin-session.ts`

- [ ] **Step 1: Write the module**

```typescript
import "server-only";

import { redirect } from "next/navigation";

import { getAdminSupabaseClient } from "./supabase-server";
import { getSupabaseServerClient } from "./supabase-ssr";

export type AdminRole = "admin" | "superadmin";

export type AdminSession = {
  userId: string;
  email: string;
  role: AdminRole;
};

/**
 * Reads the rep's Supabase session, cross-checks app.admin_users, and returns
 * a typed session if and only if the rep is active and allowlisted. Otherwise
 * returns null. Never throws.
 */
export async function getAdminSession(): Promise<AdminSession | null> {
  const supabase = await getSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return null;

  const authUid = userData.user.id;
  const authEmail = userData.user.email ?? "";

  // Cross-check goes through the service-role client so an unprivileged user
  // can never bypass the allowlist by tampering with their own auth row.
  const admin = getAdminSupabaseClient();
  const { data: row, error: rowError } = await admin
    .from("admin_users")
    .select("user_id, email, role, is_active")
    .eq("user_id", authUid)
    .maybeSingle();

  if (rowError || !row || row.is_active !== true) return null;

  const role = row.role === "superadmin" ? "superadmin" : "admin";
  return {
    userId: row.user_id as string,
    email: (row.email as string) || authEmail,
    role,
  };
}

/**
 * Server Component / Server Action guard. Redirects to /login when there is
 * no valid session. Returns a non-null AdminSession on success.
 */
export async function requireAdminSession(
  nextPath: string = "/dashboard",
): Promise<AdminSession> {
  const session = await getAdminSession();
  if (!session) {
    redirect(`/login?next=${encodeURIComponent(nextPath)}`);
  }
  return session;
}

/**
 * Stricter guard for /admin-users and its actions. Redirects an active
 * non-superadmin to /dashboard?reason=forbidden.
 */
export async function requireSuperadmin(
  nextPath: string = "/admin-users",
): Promise<AdminSession> {
  const session = await requireAdminSession(nextPath);
  if (session.role !== "superadmin") {
    redirect("/dashboard?reason=forbidden");
  }
  return session;
}
```

- [ ] **Step 2: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```
Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add admin/src/lib/admin-session.ts
git commit -m "feat(admin): add session + allowlist + superadmin guards"
```

---

### Task A1.3: Replace middleware with Supabase-aware gate

**Files:**
- Modify: `admin/src/middleware.ts`

- [ ] **Step 1: Rewrite the file**

Replace the entire contents of `admin/src/middleware.ts` with:
```typescript
import { NextResponse, type NextRequest } from "next/server";
import { createServerClient, type CookieOptions } from "@supabase/ssr";

/**
 * Admin auth gate (Phase A).
 *
 * Every request is run through Supabase to refresh the session cookie and
 * fetch the signed-in user. Unauthenticated requests are bounced to /login.
 * Allowlist (admin_users.is_active) is enforced in the page / action layer
 * via requireAdminSession() — keeping middleware on the Edge runtime free of
 * the service-role DB call.
 *
 * Public routes (no auth required): /login, /auth/callback, /denied,
 * static assets.
 */

const PUBLIC_PATHS = ["/login", "/auth/callback", "/auth/signout", "/denied"];

function isPublic(pathname: string): boolean {
  if (PUBLIC_PATHS.includes(pathname)) return true;
  return false;
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Always allow Next.js internals + public auth routes.
  if (isPublic(pathname)) {
    return NextResponse.next();
  }

  const url = process.env.SUPABASE_URL?.trim();
  const anonKey = process.env.SUPABASE_ANON_KEY?.trim();

  // Fail closed if env is missing: easier to spot than a silent open gate.
  if (!url || !anonKey) {
    return new NextResponse(
      "Admin auth misconfigured: SUPABASE_URL / SUPABASE_ANON_KEY missing.",
      { status: 500 },
    );
  }

  const response = NextResponse.next({
    request: { headers: request.headers },
  });

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options as CookieOptions);
        }
      },
    },
  });

  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    const redirectUrl = new URL("/login", request.url);
    redirectUrl.searchParams.set("next", pathname);
    return NextResponse.redirect(redirectUrl);
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)"],
};
```

- [ ] **Step 2: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```
Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add admin/src/middleware.ts
git commit -m "feat(admin): replace basic-auth shim with Supabase-aware middleware"
```

---

### Task A1.4: `/login` page + magic-link server action

**Files:**
- Create: `admin/src/app/login/page.tsx`
- Create: `admin/src/app/login/login-form.tsx`
- Create: `admin/src/app/login/actions.ts`

- [ ] **Step 1: Write the server action**

`admin/src/app/login/actions.ts`:
```typescript
"use server";

import { headers } from "next/headers";

import { getSupabaseServerClient } from "@/lib/supabase-ssr";

export type SendMagicLinkResult =
  | { ok: true }
  | { ok: false; message: string };

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export async function sendMagicLinkAction(
  rawEmail: string,
  nextPath: string,
): Promise<SendMagicLinkResult> {
  const email = (rawEmail ?? "").trim().toLowerCase();
  if (!isValidEmail(email)) {
    return { ok: false, message: "Enter a valid email address." };
  }

  const safeNext =
    nextPath && nextPath.startsWith("/") && !nextPath.startsWith("//")
      ? nextPath
      : "/dashboard";

  const requestHeaders = await headers();
  const proto = requestHeaders.get("x-forwarded-proto") ?? "https";
  const host = requestHeaders.get("host") ?? "";
  const origin = host ? `${proto}://${host}` : "";

  if (!origin) {
    return { ok: false, message: "Cannot determine site origin." };
  }

  const supabase = await getSupabaseServerClient();
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      emailRedirectTo: `${origin}/auth/callback?next=${encodeURIComponent(safeNext)}`,
      shouldCreateUser: false,
    },
  });

  if (error) {
    return { ok: false, message: error.message };
  }

  return { ok: true };
}
```

- [ ] **Step 2: Write the client form**

`admin/src/app/login/login-form.tsx`:
```typescript
"use client";

import { useState, useTransition } from "react";

import { sendMagicLinkAction } from "./actions";

type LoginFormProps = {
  nextPath: string;
};

export function LoginForm({ nextPath }: LoginFormProps) {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "sent" | "error">("idle");
  const [message, setMessage] = useState<string>("");
  const [isPending, startTransition] = useTransition();

  function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("idle");
    setMessage("");
    startTransition(async () => {
      const result = await sendMagicLinkAction(email, nextPath);
      if (result.ok) {
        setStatus("sent");
      } else {
        setStatus("error");
        setMessage(result.message);
      }
    });
  }

  if (status === "sent") {
    return (
      <div className="arena-panel bg-[var(--arena-surface)] p-6">
        <h2 className="font-[family-name:var(--font-anybody)] text-2xl font-extrabold uppercase">
          Check your inbox
        </h2>
        <p className="mt-3 text-base text-[var(--arena-ink-muted)]">
          We sent a magic link to <strong>{email}</strong>. Click it on this device to sign in.
          The link expires in 1 hour.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="arena-panel flex flex-col gap-4 bg-[var(--arena-surface)] p-6">
      <label className="flex flex-col gap-2">
        <span className="font-semibold">Work email</span>
        <input
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="arena-input"
          placeholder="you@example.com"
          disabled={isPending}
        />
      </label>
      {status === "error" ? (
        <p className="text-sm text-[var(--arena-primary-strong)]" role="alert">
          {message}
        </p>
      ) : null}
      <button
        type="submit"
        disabled={isPending}
        className="arena-button bg-[var(--arena-primary)] px-4 py-3 font-semibold"
      >
        {isPending ? "Sending…" : "Send magic link"}
      </button>
      <p className="text-xs text-[var(--arena-ink-muted)]">
        Only allowlisted admin emails can sign in. If you don't receive a link within a minute,
        check spam or contact your admin lead.
      </p>
    </form>
  );
}
```

- [ ] **Step 3: Write the page**

`admin/src/app/login/page.tsx`:
```typescript
import { LoginForm } from "./login-form";

type LoginPageProps = {
  searchParams: Promise<{ next?: string; reason?: string }>;
};

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const params = await searchParams;
  const nextPath = typeof params.next === "string" ? params.next : "/dashboard";
  const expired = params.reason === "expired";

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-6 p-5">
      <header>
        <h1 className="font-[family-name:var(--font-anybody)] text-4xl font-extrabold uppercase tracking-tight">
          MedRash Admin
        </h1>
        <p className="mt-2 text-base text-[var(--arena-ink-muted)]">
          Sign in with your work email. We&apos;ll send a one-tap link.
        </p>
      </header>
      {expired ? (
        <div
          role="status"
          className="arena-panel bg-[var(--arena-danger)] p-3 text-sm font-semibold"
        >
          Your session expired. Please sign in again.
        </div>
      ) : null}
      <LoginForm nextPath={nextPath} />
    </main>
  );
}
```

- [ ] **Step 4: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```
Expected: zero errors.

- [ ] **Step 5: Commit**

```bash
git add admin/src/app/login
git commit -m "feat(admin): /login page with magic-link server action"
```

---

### Task A1.5: `/auth/callback` + `/auth/signout` routes

**Files:**
- Create: `admin/src/app/auth/callback/route.ts`
- Create: `admin/src/app/auth/signout/route.ts`

- [ ] **Step 1: Write the callback route**

`admin/src/app/auth/callback/route.ts`:
```typescript
import { NextResponse, type NextRequest } from "next/server";

import { getSupabaseServerClient } from "@/lib/supabase-ssr";

export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const nextParam = url.searchParams.get("next");
  const safeNext =
    nextParam && nextParam.startsWith("/") && !nextParam.startsWith("//")
      ? nextParam
      : "/dashboard";

  if (!code) {
    const redirect = new URL("/login", url);
    redirect.searchParams.set("reason", "missing-code");
    return NextResponse.redirect(redirect);
  }

  const supabase = await getSupabaseServerClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    const redirect = new URL("/login", url);
    redirect.searchParams.set("reason", "exchange-failed");
    return NextResponse.redirect(redirect);
  }

  return NextResponse.redirect(new URL(safeNext, url));
}
```

- [ ] **Step 2: Write the signout route**

`admin/src/app/auth/signout/route.ts`:
```typescript
import { NextResponse, type NextRequest } from "next/server";

import { getSupabaseServerClient } from "@/lib/supabase-ssr";

export async function POST(request: NextRequest) {
  const supabase = await getSupabaseServerClient();
  await supabase.auth.signOut({ scope: "local" });
  return NextResponse.redirect(new URL("/login", request.url), { status: 303 });
}
```

- [ ] **Step 3: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```
Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add admin/src/app/auth
git commit -m "feat(admin): /auth/callback + /auth/signout routes"
```

---

### Task A1.6: `/denied` page + Allowlist enforcement in root layout

**Files:**
- Create: `admin/src/app/denied/page.tsx`

- [ ] **Step 1: Write the page**

```typescript
export default function DeniedPage() {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-6 p-5">
      <header>
        <h1 className="font-[family-name:var(--font-anybody)] text-4xl font-extrabold uppercase tracking-tight">
          Access pending or revoked
        </h1>
        <p className="mt-3 text-base text-[var(--arena-ink-muted)]">
          Your email is signed in but is not currently on the MedRash admin
          allowlist. Contact your admin lead to be invited or reactivated.
        </p>
      </header>
      <form action="/auth/signout" method="post">
        <button
          type="submit"
          className="arena-button bg-[var(--arena-surface)] px-4 py-3 font-semibold"
        >
          Sign out
        </button>
      </form>
    </main>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/src/app/denied
git commit -m "feat(admin): /denied page for non-allowlisted users"
```

---

### Task A1.7: Wire allowlist enforcement into every protected page

**Files:**
- Modify: `admin/src/app/dashboard/page.tsx`
- Modify: `admin/src/app/sessions/page.tsx`
- Modify: `admin/src/app/quiz-bank/page.tsx`
- Modify: `admin/src/app/reports/page.tsx`
- Modify: `admin/src/app/intelligence/page.tsx`

Each protected page must call `requireAdminSession()` at the top of its server-component default export. If the call returns, the rep is signed-in **and** allowlisted-active.

- [ ] **Step 1: Read each page to find its export**

Run:
```pwsh
Get-ChildItem admin/src/app -Recurse -Include page.tsx | Where-Object { $_.FullName -notmatch 'login|denied|admin-users' } | Select-Object FullName
```

- [ ] **Step 2: For each listed page, add at the very top of the `export default async function … () {` body:**

```typescript
import { redirect } from "next/navigation";
import { getAdminSession } from "@/lib/admin-session";
```
…and inside the page function body, before any data fetching:
```typescript
  const session = await getAdminSession();
  if (!session) redirect("/login");
  // allowlist check: signed in but not on admin_users (or deactivated)
  // ⇒ middleware lets them in, but admin-session returns null. Bounce to /denied.
  if (!session) redirect("/denied");
```

(The redundant null check is intentional: the first branch fires when the cookie itself is invalid; in practice middleware will have already redirected. The pattern keeps the guard tight and readable.)

Concrete diff for `admin/src/app/dashboard/page.tsx` — add the import and the two-line guard immediately inside the function body. Repeat structurally for the other four pages.

- [ ] **Step 3: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```
Expected: zero errors.

- [ ] **Step 4: Build**

Run:
```pwsh
cmd /c "cd admin && npm run build"
```
Expected: 10 routes compile; no missing-module errors.

- [ ] **Step 5: Commit**

```bash
git add admin/src/app/dashboard admin/src/app/sessions admin/src/app/quiz-bank admin/src/app/reports admin/src/app/intelligence
git commit -m "feat(admin): enforce admin_users allowlist on every protected page"
```

---

### Task A1.8: AdminUserMenu + admin-shell wiring

**Files:**
- Create: `admin/src/components/admin-user-menu.tsx`
- Modify: `admin/src/components/admin-shell.tsx`
- Modify: `admin/src/components/admin-sidebar.tsx`

- [ ] **Step 1: Write `admin/src/components/admin-user-menu.tsx`**

```typescript
"use client";

import { useState } from "react";

type AdminUserMenuProps = {
  email: string;
  role: "admin" | "superadmin";
};

export function AdminUserMenu({ email, role }: AdminUserMenuProps) {
  const [open, setOpen] = useState(false);
  const initial = (email[0] ?? "?").toUpperCase();

  return (
    <div className="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="arena-button flex items-center gap-2 bg-[var(--arena-surface)] px-3 py-2"
      >
        <span className="flex h-7 w-7 items-center justify-center rounded-full border-[2px] border-[var(--arena-outline)] bg-[var(--arena-secondary)] text-sm font-extrabold">
          {initial}
        </span>
        <span className="hidden text-sm font-semibold sm:inline">{email}</span>
      </button>
      {open ? (
        <div
          role="menu"
          className="arena-panel absolute right-0 z-40 mt-2 w-64 bg-[var(--arena-surface)] p-3"
        >
          <p className="text-sm font-semibold">{email}</p>
          <p className="text-xs uppercase text-[var(--arena-ink-muted)]">{role}</p>
          <form action="/auth/signout" method="post" className="mt-3">
            <button
              type="submit"
              className="arena-button w-full bg-[var(--arena-danger)] px-3 py-2 font-semibold"
            >
              Sign out
            </button>
          </form>
        </div>
      ) : null}
    </div>
  );
}
```

- [ ] **Step 2: Modify `admin/src/components/admin-shell.tsx` to accept and render the menu**

Change the props and header. Final file:

```typescript
"use client";

import { ReactNode, useEffect, useState } from "react";

import { AdminSidebar, type AdminSidebarUser } from "@/components/admin-sidebar";
import { AdminUserMenu } from "@/components/admin-user-menu";

type AdminShellProps = {
  title: string;
  subtitle: string;
  actions?: ReactNode;
  children: ReactNode;
  user: AdminSidebarUser;
};

export function AdminShell({ title, subtitle, actions, children, user }: AdminShellProps) {
  const [drawerOpen, setDrawerOpen] = useState(false);

  useEffect(() => {
    if (!drawerOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [drawerOpen]);

  return (
    <div className="min-h-screen">
      <main className="mx-auto grid w-full max-w-[1440px] gap-5 p-4 lg:grid-cols-[280px_1fr] lg:p-5">
        <div className="hidden lg:block">
          <AdminSidebar user={user} />
        </div>
        <div className="flex min-w-0 flex-col gap-5">
          <header className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
            <div className="flex items-start gap-3">
              <button
                type="button"
                aria-label="Open navigation"
                onClick={() => setDrawerOpen(true)}
                className="arena-button flex h-11 w-11 shrink-0 items-center justify-center bg-[var(--arena-surface)] lg:hidden"
              >
                <span aria-hidden="true" className="text-xl font-extrabold leading-none">≡</span>
              </button>
              <div className="min-w-0">
                <h1 className="font-[family-name:var(--font-anybody)] text-3xl font-extrabold uppercase tracking-tight md:text-4xl">
                  {title}
                </h1>
                <p className="mt-2 max-w-3xl text-base text-[var(--arena-ink-muted)]">{subtitle}</p>
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-3">
              {actions}
              <AdminUserMenu email={user.email} role={user.role} />
            </div>
          </header>
          {children}
        </div>
      </main>

      {drawerOpen ? (
        <div className="fixed inset-0 z-50 lg:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
          <button
            type="button"
            aria-label="Close navigation"
            onClick={() => setDrawerOpen(false)}
            className="absolute inset-0 bg-black/40"
          />
          <div className="absolute inset-y-0 left-0 w-[min(320px,85vw)] overflow-y-auto bg-[var(--arena-background)] p-4 shadow-2xl">
            <AdminSidebar user={user} onClose={() => setDrawerOpen(false)} />
          </div>
        </div>
      ) : null}
    </div>
  );
}
```

- [ ] **Step 3: Modify `admin/src/components/admin-sidebar.tsx` to take the live user + filter nav by role**

```typescript
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { adminNavigation } from "@/lib/design-tokens";

export type AdminSidebarUser = {
  email: string;
  role: "admin" | "superadmin";
};

type AdminSidebarProps = {
  user: AdminSidebarUser;
  onClose?: () => void;
};

export function AdminSidebar({ user, onClose }: AdminSidebarProps) {
  const pathname = usePathname();
  const initial = (user.email[0] ?? "?").toUpperCase();

  const items = adminNavigation.filter((item) => {
    if (item.requiresRole === "superadmin") return user.role === "superadmin";
    return true;
  });

  return (
    <aside className="arena-panel flex h-fit flex-col gap-6 bg-[var(--arena-surface)] p-5 lg:sticky lg:top-5">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-full border-[3px] border-[var(--arena-outline)] bg-[var(--arena-secondary)] font-[family-name:var(--font-anybody)] text-lg font-extrabold">
            {initial}
          </div>
          <div className="min-w-0">
            <p className="truncate font-[family-name:var(--font-anybody)] text-base font-extrabold uppercase leading-none">
              {user.email}
            </p>
            <p className="text-sm text-[var(--arena-ink-muted)]">{user.role}</p>
          </div>
        </div>
        {onClose ? (
          <button
            type="button"
            aria-label="Close navigation"
            onClick={onClose}
            className="arena-button flex h-9 w-9 items-center justify-center bg-[var(--arena-surface)] lg:hidden"
          >
            <span aria-hidden="true" className="text-lg font-extrabold leading-none">×</span>
          </button>
        ) : null}
      </div>
      <nav className="flex flex-col gap-3">
        {items.map((item) => {
          const active = pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onClose}
              className={[
                "arena-button px-4 py-3 font-semibold",
                active
                  ? "bg-[var(--arena-secondary)]"
                  : "bg-[var(--arena-surface)] hover:bg-[var(--arena-panel)]",
              ].join(" ")}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
```

- [ ] **Step 4: Update `admin/src/lib/design-tokens.ts` to add the `requiresRole` field and the Admin Users link**

```typescript
export const designTokens = {
  colors: {
    background: "#f9f9f9",
    surface: "#ffffff",
    surfaceMuted: "#f3f3f3",
    panel: "#eeeeee",
    ink: "#1b1b1b",
    inkMuted: "#4c4735",
    outline: "#111111",
    primary: "#ffde59",
    primaryStrong: "#705d00",
    secondary: "#73f6fb",
    tertiary: "#ffd4e7",
    danger: "#ffd8d2",
    success: "#d8ffe4",
  },
  radius: {
    lg: "16px",
    md: "12px",
  },
  shadow: {
    hard: "4px 4px 0 0 #111111",
  },
  spacing: {
    page: "20px",
  },
} as const;

export type AdminNavItem = {
  href: string;
  label: string;
  requiresRole?: "superadmin";
};

export const adminNavigation: readonly AdminNavItem[] = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/quiz-bank", label: "Quiz Bank" },
  { href: "/sessions", label: "Sessions" },
  { href: "/reports", label: "Reports" },
  { href: "/intelligence", label: "Intelligence" },
  { href: "/admin-users", label: "Admin Users", requiresRole: "superadmin" },
] as const;
```

- [ ] **Step 5: Update every page that renders `<AdminShell>` to pass the `user` prop**

For each of `admin/src/app/dashboard/page.tsx`, `sessions/page.tsx`, `quiz-bank/page.tsx`, `reports/page.tsx`, `intelligence/page.tsx`:
1. The page already calls `requireAdminSession()` (from Task A1.7) — change that call so it captures the return value: `const session = await requireAdminSession();`.
2. Change `<AdminShell title="…" subtitle="…">` to `<AdminShell title="…" subtitle="…" user={{ email: session.email, role: session.role }}>`.

- [ ] **Step 6: Typecheck + build**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
cmd /c "cd admin && npm run build"
```
Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add admin/src/components admin/src/lib/design-tokens.ts admin/src/app
git commit -m "feat(admin): show signed-in identity + role-aware sidebar"
```

---

### Task A1.9: Manual smoke test (no real Supabase yet)

This task is verification only — no code change.

- [ ] **Step 1: Set local env in `admin/.env.local`** (do not commit):
```
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_ANON_KEY=<paste anon key>
SUPABASE_SERVICE_ROLE_KEY=<paste service role>
MEDRASH_ADMIN_WRITE_KEY=<existing>
MEDRASH_APP_PUBLIC_BASE_URL=http://localhost:5000
```

- [ ] **Step 2: Run `scripts/seed-admin.mjs` against the dev project**

```pwsh
$env:SUPABASE_URL = "https://<ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "<service role>"
$env:ADMIN_BOOTSTRAP_EMAIL = "your-email@yours.com"
node ./scripts/seed-admin.mjs
Remove-Item Env:SUPABASE_URL, Env:SUPABASE_SERVICE_ROLE_KEY, Env:ADMIN_BOOTSTRAP_EMAIL
```
Expected: prints user_id, role=superadmin, active=true.

- [ ] **Step 3: Start the admin app**

```pwsh
cmd /c "cd admin && npm run dev"
```

- [ ] **Step 4: Verify the flow**

In a browser:
1. Visit http://localhost:3000/dashboard → bounced to `/login?next=%2Fdashboard`. PASS.
2. Submit your bootstrap email → "Check your inbox". PASS.
3. Open the magic link from your inbox → landed on `/dashboard`. PASS.
4. Refresh `/dashboard` → still signed in. PASS.
5. Hit `/admin-users` → 404 (page not built yet — A2). Expected.
6. Click the user menu → "Sign out" → bounced back to `/login`. PASS.

Document any failure inline before proceeding to A2.

---

## A2 — `/admin-users` + default-mine toggle + identity-aware writes

### Task A2.1: `admin-users-queries.ts` + `created-by.ts` helpers

**Files:**
- Create: `admin/src/lib/admin-users-queries.ts`
- Create: `admin/src/lib/created-by.ts`

- [ ] **Step 1: Write `admin/src/lib/created-by.ts`**

```typescript
export const PRE_AUTH_SEED_LABEL = "Pre-auth seed";

export function formatCreatedBy(
  email: string | null | undefined,
): string {
  if (!email || email.trim().length === 0) return PRE_AUTH_SEED_LABEL;
  return email;
}
```

- [ ] **Step 2: Write `admin/src/lib/admin-users-queries.ts`**

```typescript
import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type AdminUserRow = {
  userId: string;
  email: string;
  role: "admin" | "superadmin";
  isActive: boolean;
  invitedByEmail: string | null;
  invitedAt: string | null;
  createdAt: string;
};

type Row = {
  user_id: string;
  email: string;
  role: string;
  is_active: boolean;
  invited_by: string | null;
  invited_at: string | null;
  created_at: string;
  inviter:
    | { email: string | null }
    | Array<{ email: string | null }>
    | null;
};

/**
 * List every admin_users row, newest invitation first, with the inviting
 * admin's email resolved via a self-join.
 */
export async function listAdminUsers(): Promise<AdminUserRow[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("admin_users")
    .select(
      "user_id, email, role, is_active, invited_by, invited_at, created_at, inviter:admin_users!admin_users_invited_by_fkey(email)",
    )
    .order("created_at", { ascending: false });

  if (error) {
    throw new Error(`Failed to load admin users: ${error.message}`);
  }

  const rows = (data as Row[] | null) ?? [];
  return rows.map((row) => {
    const inviterRel = Array.isArray(row.inviter) ? row.inviter[0] : row.inviter;
    return {
      userId: row.user_id,
      email: row.email,
      role: row.role === "superadmin" ? "superadmin" : "admin",
      isActive: row.is_active,
      invitedByEmail: inviterRel?.email ?? null,
      invitedAt: row.invited_at,
      createdAt: row.created_at,
    };
  });
}

/**
 * Count of active superadmins. Used to prevent the system from ending up
 * with zero superadmins via deactivation or demotion.
 */
export async function countActiveSuperadmins(): Promise<number> {
  const supabase = getAdminSupabaseClient();
  const { count, error } = await supabase
    .from("admin_users")
    .select("user_id", { count: "exact", head: true })
    .eq("role", "superadmin")
    .eq("is_active", true);
  if (error) {
    throw new Error(`Failed to count superadmins: ${error.message}`);
  }
  return count ?? 0;
}
```

- [ ] **Step 3: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```

- [ ] **Step 4: Commit**

```bash
git add admin/src/lib/admin-users-queries.ts admin/src/lib/created-by.ts
git commit -m "feat(admin): admin_users query helpers + created-by formatter"
```

---

### Task A2.2: `/admin-users` server actions

**Files:**
- Create: `admin/src/app/admin-users/actions.ts`

- [ ] **Step 1: Write the actions**

```typescript
"use server";

import { revalidatePath } from "next/cache";

import {
  countActiveSuperadmins,
  type AdminUserRow,
} from "@/lib/admin-users-queries";
import { requireSuperadmin } from "@/lib/admin-session";
import { getAdminSupabaseClient } from "@/lib/supabase-server";
import { createClient } from "@supabase/supabase-js";

export type AdminUsersActionResult =
  | { ok: true }
  | { ok: false; message: string };

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function getAuthAdminClient() {
  const url = process.env.SUPABASE_URL?.trim();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!url || !serviceRoleKey) {
    throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY required.");
  }
  // The `auth.admin` API lives on a default-schema client, NOT on the
  // app-schema client used for table ops.
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function inviteAdminAction(
  rawEmail: string,
  rawRole: "admin" | "superadmin",
): Promise<AdminUsersActionResult> {
  const me = await requireSuperadmin();
  const email = (rawEmail ?? "").trim().toLowerCase();
  const role = rawRole === "superadmin" ? "superadmin" : "admin";

  if (!isValidEmail(email)) {
    return { ok: false, message: "Enter a valid email address." };
  }

  try {
    const authAdmin = getAuthAdminClient();
    const { data: inviteData, error: inviteError } =
      await authAdmin.auth.admin.inviteUserByEmail(email);
    if (inviteError && !/already (registered|exists)/i.test(inviteError.message)) {
      return { ok: false, message: `Invite failed: ${inviteError.message}` };
    }

    let userId = inviteData?.user?.id ?? null;
    if (!userId) {
      const { data: list, error: listError } = await authAdmin.auth.admin.listUsers({
        page: 1,
        perPage: 1000,
      });
      if (listError) {
        return { ok: false, message: `Lookup failed: ${listError.message}` };
      }
      userId =
        list.users.find((u) => (u.email ?? "").toLowerCase() === email)?.id ?? null;
    }
    if (!userId) {
      return { ok: false, message: "Could not resolve user id after invite." };
    }

    const supabase = getAdminSupabaseClient();
    const { error: upsertError } = await supabase.from("admin_users").upsert(
      {
        user_id: userId,
        email,
        role,
        is_active: true,
        invited_by: me.userId,
        invited_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );
    if (upsertError) {
      return { ok: false, message: `Allowlist write failed: ${upsertError.message}` };
    }

    revalidatePath("/admin-users");
    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Invite failed.",
    };
  }
}

async function updateAdminUser(
  targetUserId: string,
  patch: Partial<Pick<AdminUserRow, "isActive" | "role">>,
): Promise<AdminUsersActionResult> {
  const me = await requireSuperadmin();
  if (targetUserId === me.userId) {
    return {
      ok: false,
      message: "You cannot change your own status. Ask another superadmin.",
    };
  }

  const supabase = getAdminSupabaseClient();

  // Pre-flight: if this update would leave zero active superadmins, refuse.
  if (patch.isActive === false || patch.role === "admin") {
    const { data: target, error: targetError } = await supabase
      .from("admin_users")
      .select("role, is_active")
      .eq("user_id", targetUserId)
      .maybeSingle();
    if (targetError || !target) {
      return { ok: false, message: "Target admin not found." };
    }
    const targetIsActiveSuperadmin =
      target.role === "superadmin" && target.is_active === true;
    if (targetIsActiveSuperadmin) {
      const active = await countActiveSuperadmins();
      if (active <= 1) {
        return {
          ok: false,
          message: "Refusing: would leave zero active superadmins.",
        };
      }
    }
  }

  const update: Record<string, unknown> = {};
  if (typeof patch.isActive === "boolean") update.is_active = patch.isActive;
  if (patch.role) update.role = patch.role;

  const { error } = await supabase
    .from("admin_users")
    .update(update)
    .eq("user_id", targetUserId);
  if (error) {
    return { ok: false, message: `Update failed: ${error.message}` };
  }
  revalidatePath("/admin-users");
  return { ok: true };
}

export async function deactivateAdminAction(
  targetUserId: string,
): Promise<AdminUsersActionResult> {
  return updateAdminUser(targetUserId, { isActive: false });
}

export async function reactivateAdminAction(
  targetUserId: string,
): Promise<AdminUsersActionResult> {
  return updateAdminUser(targetUserId, { isActive: true });
}

export async function promoteAdminAction(
  targetUserId: string,
): Promise<AdminUsersActionResult> {
  return updateAdminUser(targetUserId, { role: "superadmin" });
}

export async function demoteAdminAction(
  targetUserId: string,
): Promise<AdminUsersActionResult> {
  return updateAdminUser(targetUserId, { role: "admin" });
}
```

- [ ] **Step 2: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```

- [ ] **Step 3: Commit**

```bash
git add admin/src/app/admin-users/actions.ts
git commit -m "feat(admin): admin-users invite/deactivate/promote actions"
```

---

### Task A2.3: `/admin-users` page + UI

**Files:**
- Create: `admin/src/app/admin-users/page.tsx`
- Create: `admin/src/app/admin-users/invite-form.tsx`
- Create: `admin/src/app/admin-users/admin-row-actions.tsx`

- [ ] **Step 1: Write the invite form**

`admin/src/app/admin-users/invite-form.tsx`:
```typescript
"use client";

import { useState, useTransition } from "react";

import { inviteAdminAction } from "./actions";

export function InviteForm() {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"admin" | "superadmin">("admin");
  const [message, setMessage] = useState<string>("");
  const [isPending, startTransition] = useTransition();

  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setMessage("");
    startTransition(async () => {
      const result = await inviteAdminAction(email, role);
      if (result.ok) {
        setEmail("");
        setMessage(`Invited ${email}.`);
      } else {
        setMessage(result.message);
      }
    });
  }

  return (
    <form onSubmit={onSubmit} className="arena-panel flex flex-col gap-3 bg-[var(--arena-surface)] p-4 md:flex-row md:items-end">
      <label className="flex flex-1 flex-col gap-2">
        <span className="font-semibold">Email</span>
        <input
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="arena-input"
          placeholder="rep@example.com"
          disabled={isPending}
        />
      </label>
      <label className="flex flex-col gap-2">
        <span className="font-semibold">Role</span>
        <select
          value={role}
          onChange={(e) => setRole(e.target.value as "admin" | "superadmin")}
          className="arena-input"
          disabled={isPending}
        >
          <option value="admin">admin</option>
          <option value="superadmin">superadmin</option>
        </select>
      </label>
      <button
        type="submit"
        disabled={isPending}
        className="arena-button bg-[var(--arena-primary)] px-4 py-3 font-semibold"
      >
        {isPending ? "Inviting…" : "Invite"}
      </button>
      {message ? (
        <p className="w-full text-sm text-[var(--arena-ink-muted)] md:w-auto" role="status">
          {message}
        </p>
      ) : null}
    </form>
  );
}
```

- [ ] **Step 2: Write the row actions**

`admin/src/app/admin-users/admin-row-actions.tsx`:
```typescript
"use client";

import { useTransition } from "react";

import {
  deactivateAdminAction,
  demoteAdminAction,
  promoteAdminAction,
  reactivateAdminAction,
} from "./actions";

type AdminRowActionsProps = {
  userId: string;
  isActive: boolean;
  role: "admin" | "superadmin";
  isSelf: boolean;
};

export function AdminRowActions({ userId, isActive, role, isSelf }: AdminRowActionsProps) {
  const [isPending, startTransition] = useTransition();

  if (isSelf) {
    return <span className="text-xs text-[var(--arena-ink-muted)]">(you)</span>;
  }

  function run(action: () => Promise<{ ok: boolean; message?: string }>) {
    startTransition(async () => {
      const result = await action();
      if (!result.ok) {
        alert(result.message ?? "Action failed.");
      }
    });
  }

  return (
    <div className="flex flex-wrap gap-2">
      {isActive ? (
        <button
          type="button"
          disabled={isPending}
          onClick={() => run(() => deactivateAdminAction(userId))}
          className="arena-button bg-[var(--arena-danger)] px-3 py-1 text-sm font-semibold"
        >
          Deactivate
        </button>
      ) : (
        <button
          type="button"
          disabled={isPending}
          onClick={() => run(() => reactivateAdminAction(userId))}
          className="arena-button bg-[var(--arena-success)] px-3 py-1 text-sm font-semibold"
        >
          Reactivate
        </button>
      )}
      {role === "admin" ? (
        <button
          type="button"
          disabled={isPending}
          onClick={() => run(() => promoteAdminAction(userId))}
          className="arena-button bg-[var(--arena-surface)] px-3 py-1 text-sm font-semibold"
        >
          Promote
        </button>
      ) : (
        <button
          type="button"
          disabled={isPending}
          onClick={() => run(() => demoteAdminAction(userId))}
          className="arena-button bg-[var(--arena-surface)] px-3 py-1 text-sm font-semibold"
        >
          Demote
        </button>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Write the page**

`admin/src/app/admin-users/page.tsx`:
```typescript
import { AdminShell } from "@/components/admin-shell";
import { listAdminUsers } from "@/lib/admin-users-queries";
import { requireSuperadmin } from "@/lib/admin-session";

import { AdminRowActions } from "./admin-row-actions";
import { InviteForm } from "./invite-form";

export const dynamic = "force-dynamic";

export default async function AdminUsersPage() {
  const me = await requireSuperadmin();
  const users = await listAdminUsers();

  return (
    <AdminShell
      title="Admin users"
      subtitle="Invite, deactivate, and promote admins. Superadmin only."
      user={{ email: me.email, role: me.role }}
    >
      <InviteForm />

      <section className="arena-panel overflow-x-auto bg-[var(--arena-surface)] p-4">
        <table className="w-full min-w-[640px] text-left">
          <thead>
            <tr className="border-b-[3px] border-[var(--arena-outline)] text-sm uppercase">
              <th className="px-2 py-2">Email</th>
              <th className="px-2 py-2">Role</th>
              <th className="px-2 py-2">Active</th>
              <th className="px-2 py-2">Invited by</th>
              <th className="px-2 py-2">Invited at</th>
              <th className="px-2 py-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.userId} className="border-b border-[var(--arena-panel)]">
                <td className="px-2 py-2 font-semibold">{u.email}</td>
                <td className="px-2 py-2 uppercase text-sm">{u.role}</td>
                <td className="px-2 py-2">{u.isActive ? "yes" : "no"}</td>
                <td className="px-2 py-2 text-sm">{u.invitedByEmail ?? "—"}</td>
                <td className="px-2 py-2 text-sm">
                  {u.invitedAt ? new Date(u.invitedAt).toLocaleString() : "—"}
                </td>
                <td className="px-2 py-2">
                  <AdminRowActions
                    userId={u.userId}
                    isActive={u.isActive}
                    role={u.role}
                    isSelf={u.userId === me.userId}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </AdminShell>
  );
}
```

- [ ] **Step 4: Typecheck + build**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
cmd /c "cd admin && npm run build"
```
Expected: 11 routes (added `/admin-users`), no errors.

- [ ] **Step 5: Commit**

```bash
git add admin/src/app/admin-users
git commit -m "feat(admin): /admin-users page (superadmin-only)"
```

---

### Task A2.4: `ScopeToggle` + default-mine query helper

**Files:**
- Create: `admin/src/components/scope-toggle.tsx`

- [ ] **Step 1: Write the component**

```typescript
"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";

export type Scope = "mine" | "all";

export function parseScopeParam(raw: string | string[] | undefined): Scope {
  const v = Array.isArray(raw) ? raw[0] : raw;
  return v === "all" ? "all" : "mine";
}

export function ScopeToggle({ current }: { current: Scope }) {
  const pathname = usePathname();
  const search = useSearchParams();

  function hrefFor(next: Scope): string {
    const params = new URLSearchParams(search?.toString() ?? "");
    if (next === "mine") {
      params.delete("scope");
    } else {
      params.set("scope", "all");
    }
    const query = params.toString();
    return query ? `${pathname}?${query}` : pathname;
  }

  return (
    <div className="arena-panel inline-flex gap-1 bg-[var(--arena-surface)] p-1" role="group" aria-label="Scope">
      <Link
        href={hrefFor("mine")}
        prefetch={false}
        className={[
          "arena-button px-3 py-1 text-sm font-semibold",
          current === "mine" ? "bg-[var(--arena-secondary)]" : "bg-[var(--arena-surface)]",
        ].join(" ")}
      >
        Mine
      </Link>
      <Link
        href={hrefFor("all")}
        prefetch={false}
        className={[
          "arena-button px-3 py-1 text-sm font-semibold",
          current === "all" ? "bg-[var(--arena-secondary)]" : "bg-[var(--arena-surface)]",
        ].join(" ")}
      >
        All
      </Link>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/src/components/scope-toggle.tsx
git commit -m "feat(admin): ScopeToggle component + parseScopeParam helper"
```

---

### Task A2.5: Plumb scope into session & quiz-bank queries

**Files:**
- Modify: `admin/src/lib/session-queries.ts`
- Modify: `admin/src/lib/quiz-bank-queries.ts`

- [ ] **Step 1: Modify `listAdminSessions` to accept `{ scope, userId }`**

Replace the existing function in `session-queries.ts`:
```typescript
export type ListScope = { scope: "mine" | "all"; userId: string };

export async function listAdminSessions(
  filter: ListScope,
): Promise<AdminSessionRow[]> {
  const supabase = getAdminSupabaseClient();
  let query = supabase
    .from("sessions")
    .select(
      "id, name, join_code, host_name, starts_at, ends_at, created_at, quiz_id, created_by, quizzes(title), attempts(id)",
    )
    .order("created_at", { ascending: false })
    .limit(50);

  if (filter.scope === "mine") {
    query = query.eq("created_by", filter.userId);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(`Failed to load sessions: ${error.message}`);
  }

  const rows = (data as SessionRow[] | null) ?? [];
  const nowMs = Date.now();

  return rows.map((row) => {
    const quizRel = Array.isArray(row.quizzes) ? row.quizzes[0] : row.quizzes;
    return {
      id: row.id,
      name: row.name,
      joinCode: row.join_code,
      hostName: row.host_name,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      createdAt: row.created_at,
      quizId: row.quiz_id,
      quizTitle: quizRel?.title ?? "(unknown quiz)",
      attemptCount: (row.attempts ?? []).length,
      isActiveNow: isActiveNow(row.starts_at, row.ends_at, nowMs),
    };
  });
}
```

- [ ] **Step 2: Modify `listAdminQuizzes` to accept the same `ListScope`**

Replace in `quiz-bank-queries.ts`:
```typescript
export type ListScope = { scope: "mine" | "all"; userId: string };

export async function listAdminQuizzes(
  filter: ListScope,
): Promise<AdminQuizSummary[]> {
  const supabase = getAdminSupabaseClient();
  let query = supabase
    .from("quizzes")
    .select(
      "id, slug, title, category, product, summary, question_count_default, is_active, updated_at, created_by, questions(id, prompt, position)",
    )
    .order("updated_at", { ascending: false });

  if (filter.scope === "mine") {
    query = query.eq("created_by", filter.userId);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(`Failed to load admin quizzes: ${error.message}`);
  }

  const rows = (data as QuizRow[] | null) ?? [];

  return rows.map((row) => {
    const questions = (row.questions ?? [])
      .slice()
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
    return {
      id: row.id,
      slug: row.slug,
      title: row.title,
      category: row.category ?? "",
      product: row.product ?? "",
      summary: row.summary ?? "",
      questionCount: questions.length,
      questionCountDefault: row.question_count_default ?? 0,
      isActive: row.is_active ?? false,
      updatedAt: row.updated_at ?? "",
      sampleQuestions: questions
        .slice(0, 2)
        .map((q) => (q.prompt ?? "").trim())
        .filter((p) => p.length > 0),
    };
  });
}
```

- [ ] **Step 3: Update the `QuizRow` type alias at the top of `quiz-bank-queries.ts` to include `created_by: string | null`**

Add `created_by: string | null;` inside the `QuizRow` type.

- [ ] **Step 4: Same for `SessionRow` in `session-queries.ts`** — add `created_by: string | null;`.

- [ ] **Step 5: Typecheck**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
```

- [ ] **Step 6: Commit**

```bash
git add admin/src/lib/session-queries.ts admin/src/lib/quiz-bank-queries.ts
git commit -m "feat(admin): scope filter (mine/all) in session + quiz queries"
```

---

### Task A2.6: Wire `<ScopeToggle>` into pages

**Files:**
- Modify: `admin/src/app/sessions/page.tsx`
- Modify: `admin/src/app/quiz-bank/page.tsx`
- Modify: `admin/src/app/dashboard/page.tsx`

For each page:

1. Change the function signature to accept `searchParams`:
   ```typescript
   type Props = { searchParams: Promise<{ scope?: string }> };
   export default async function Page({ searchParams }: Props) {
   ```
2. Parse the scope and the session, then pass into the query helper:
   ```typescript
   const params = await searchParams;
   const session = await requireAdminSession();
   const scope = parseScopeParam(params.scope);
   const rows = await listAdminSessions({ scope, userId: session.userId });
   ```
3. Render the toggle in the page header `actions`:
   ```tsx
   <AdminShell
     title="Sessions"
     subtitle="…"
     user={{ email: session.email, role: session.role }}
     actions={<ScopeToggle current={scope} />}
   >
   ```

Repeat structurally for `quiz-bank/page.tsx` (use `listAdminQuizzes`) and `dashboard/page.tsx` (whatever its current data source — the same `{ scope, userId }` shape must be threaded through).

- [ ] **Step 4: Typecheck + build**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
cmd /c "cd admin && npm run build"
```
Expected: zero errors; pages compile.

- [ ] **Step 5: Commit**

```bash
git add admin/src/app/sessions/page.tsx admin/src/app/quiz-bank/page.tsx admin/src/app/dashboard/page.tsx
git commit -m "feat(admin): default-mine ScopeToggle on sessions/quiz-bank/dashboard"
```

---

### Task A2.7: Set `created_by` on every server-action insert

**Files:**
- Modify: `admin/src/lib/session-create.ts`
- Modify: `admin/src/lib/quiz-write.ts`
- Modify: `admin/src/app/sessions/actions.ts`
- Modify: `admin/src/app/quiz-bank/actions.ts`

- [ ] **Step 1: Extend `CreateSessionInput` with `createdBy`**

In `session-create.ts`, change:
```typescript
export type CreateSessionInput = {
  quizId: string;
  name: string;
  hostName: string | null;
  startsAt: string | null;
  endsAt: string | null;
  metadata: Record<string, unknown>;
  createdBy: string; // verified admin user id (auth.uid)
};
```

Update `parseCreateSessionInput` to **ignore** any `raw.createdBy` and accept it from a second arg:
```typescript
export function parseCreateSessionInput(
  raw: Record<string, unknown>,
  createdBy: string,
): CreateSessionInput {
  // …existing parsing of quizId/name/hostName/startsAt/endsAt/metadata unchanged…
  return { quizId, name, hostName, startsAt, endsAt, metadata, createdBy };
}
```

And in `createSessionRecord`, add `created_by: input.createdBy` to the `.insert({ … })` payload.

- [ ] **Step 2: Modify `admin/src/app/sessions/actions.ts` to pass the verified user id**

```typescript
"use server";

import { revalidatePath } from "next/cache";

import { requireAdminSession } from "@/lib/admin-session";
import {
  createSessionRecord,
  parseCreateSessionInput,
  type CreateSessionResult,
} from "@/lib/session-create";

export type CreateSessionActionResult =
  | { ok: true; data: CreateSessionResult }
  | { ok: false; message: string };

export async function createSessionAction(
  rawInput: Record<string, unknown>,
): Promise<CreateSessionActionResult> {
  const session = await requireAdminSession();

  let parsed;
  try {
    parsed = parseCreateSessionInput(rawInput, session.userId);
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Invalid session input.",
    };
  }

  try {
    const data = await createSessionRecord(parsed);
    revalidatePath("/sessions");
    return { ok: true, data };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Failed to create session.",
    };
  }
}
```

- [ ] **Step 3: Apply the same pattern to `quiz-write.ts`**

Add `createdBy: string` to `CreateQuizInput`, `CreateQuestionInput`, and `BulkQuestionInput`. In each `createQuizRecord` / `createQuestionRecord` / `bulkCreateQuestions` insert call, add `created_by: input.createdBy`. Update the parse functions to take `createdBy` as a second arg and ignore any client-supplied field.

- [ ] **Step 4: Modify `admin/src/app/quiz-bank/actions.ts` to thread `session.userId` through every parse call**

Wrap each existing parse call site as:
```typescript
const session = await requireAdminSession();
const parsed = parseCreateQuizInput(raw, session.userId);
```

- [ ] **Step 5: Typecheck + build**

Run:
```pwsh
cmd /c "cd admin && npm run typecheck"
cmd /c "cd admin && npm run build"
```
Expected: zero errors. Existing Phase 4 tests for `parseCreateQuizInput` (if any) may need a stub `userId` arg — update accordingly.

- [ ] **Step 6: Commit**

```bash
git add admin/src/lib/session-create.ts admin/src/lib/quiz-write.ts admin/src/app/sessions/actions.ts admin/src/app/quiz-bank/actions.ts
git commit -m "feat(admin): set created_by from verified session on every insert"
```

---

## A3 — Defense-in-depth on Netlify write functions

### Task A3.1: Write the failing test for `requireAdminUserSession`

**Files:**
- Create: `admin/netlify/functions/_shared/admin-user-session.test.ts`

- [ ] **Step 1: Write the test**

```typescript
import { describe, expect, it, vi, beforeEach } from "vitest";

import type { HandlerEvent } from "./http";

// Mock the supabase admin client. Each test sets the desired behavior.
const getUserMock = vi.fn();
const fromMock = vi.fn();

vi.mock("./supabase", () => ({
  getSupabaseAdminClient: () => ({
    auth: { getUser: getUserMock },
    from: fromMock,
  }),
}));

import { requireAdminUserSession } from "./admin-user-session";

function makeEvent(overrides: Partial<HandlerEvent> = {}): HandlerEvent {
  return {
    httpMethod: "POST",
    headers: {
      "x-medrash-admin-write-key": "test-write-key",
      authorization: "Bearer test-jwt",
    },
    body: null,
    ...overrides,
  };
}

beforeEach(() => {
  process.env.MEDRASH_ADMIN_WRITE_KEY = "test-write-key";
  getUserMock.mockReset();
  fromMock.mockReset();
});

describe("requireAdminUserSession", () => {
  it("returns 401 when shared secret is missing or wrong", async () => {
    const event = makeEvent({
      headers: { authorization: "Bearer test-jwt" },
    });
    const result = await requireAdminUserSession(event);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(401);
  });

  it("returns 401 when Authorization header is missing", async () => {
    const event = makeEvent({
      headers: { "x-medrash-admin-write-key": "test-write-key" },
    });
    const result = await requireAdminUserSession(event);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(401);
  });

  it("returns 401 when JWT does not resolve to a user", async () => {
    getUserMock.mockResolvedValueOnce({
      data: { user: null },
      error: { message: "bad jwt" },
    });
    const result = await requireAdminUserSession(makeEvent());
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(401);
  });

  it("returns 403 when user is not in admin_users", async () => {
    getUserMock.mockResolvedValueOnce({
      data: { user: { id: "u1", email: "x@y.com" } },
      error: null,
    });
    fromMock.mockReturnValueOnce({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: null, error: null }),
        }),
      }),
    });
    const result = await requireAdminUserSession(makeEvent());
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(403);
  });

  it("returns 403 when user is deactivated", async () => {
    getUserMock.mockResolvedValueOnce({
      data: { user: { id: "u1", email: "x@y.com" } },
      error: null,
    });
    fromMock.mockReturnValueOnce({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({
            data: { is_active: false, role: "admin" },
            error: null,
          }),
        }),
      }),
    });
    const result = await requireAdminUserSession(makeEvent());
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(403);
  });

  it("returns userId + email + role on success", async () => {
    getUserMock.mockResolvedValueOnce({
      data: { user: { id: "u1", email: "x@y.com" } },
      error: null,
    });
    fromMock.mockReturnValueOnce({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({
            data: { is_active: true, role: "superadmin" },
            error: null,
          }),
        }),
      }),
    });
    const result = await requireAdminUserSession(makeEvent());
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.userId).toBe("u1");
      expect(result.email).toBe("x@y.com");
      expect(result.role).toBe("superadmin");
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails (module not yet created)**

Run:
```pwsh
cmd /c "cd admin && npm test"
```
Expected: FAIL with "Cannot find module './admin-user-session'".

---

### Task A3.2: Implement `requireAdminUserSession`

**Files:**
- Create: `admin/netlify/functions/_shared/admin-user-session.ts`

- [ ] **Step 1: Write the minimal implementation**

```typescript
import { getSupabaseAdminClient } from "./supabase";
import { HandlerEvent, HandlerResponse, jsonResponse } from "./http";

export type AdminUserSessionResult =
  | { ok: true; userId: string; email: string; role: "admin" | "superadmin" }
  | { ok: false; response: HandlerResponse };

function getHeader(event: HandlerEvent, name: string): string {
  const headers = event.headers ?? {};
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === name.toLowerCase() && typeof value === "string") {
      return value;
    }
  }
  return "";
}

/**
 * Defense-in-depth gate for admin-write Netlify functions.
 *
 * Requires BOTH:
 *  1. x-medrash-admin-write-key header == MEDRASH_ADMIN_WRITE_KEY (network perimeter).
 *  2. Authorization: Bearer <jwt> that resolves to a user via Supabase auth.getUser(),
 *     AND that user has an active row in app.admin_users.
 *
 * Returns the verified userId + email + role on success, or an HTTP response
 * for the caller to forward on failure.
 */
export async function requireAdminUserSession(
  event: HandlerEvent,
): Promise<AdminUserSessionResult> {
  const writeKey = process.env.MEDRASH_ADMIN_WRITE_KEY?.trim();
  const presentedWriteKey = getHeader(event, "x-medrash-admin-write-key").trim();
  if (!writeKey || !presentedWriteKey || presentedWriteKey !== writeKey) {
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: "UNAUTHORIZED_ADMIN_WRITE",
        message: "Unauthorized admin write request.",
      }),
    };
  }

  const authHeader = getHeader(event, "authorization");
  const match = /^Bearer\s+(.+)$/i.exec(authHeader);
  const jwt = match ? match[1].trim() : "";
  if (!jwt) {
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: "MISSING_BEARER_JWT",
        message: "Authorization: Bearer <jwt> required.",
      }),
    };
  }

  const supabase = getSupabaseAdminClient();
  const { data, error } = await supabase.auth.getUser(jwt);
  if (error || !data?.user) {
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: "INVALID_JWT",
        message: error?.message ?? "JWT did not resolve to a user.",
      }),
    };
  }

  const authUserId = data.user.id;
  const authEmail = data.user.email ?? "";

  const { data: row, error: rowError } = await supabase
    .from("admin_users")
    .select("is_active, role")
    .eq("user_id", authUserId)
    .maybeSingle();

  if (rowError) {
    return {
      ok: false,
      response: jsonResponse(500, {
        ok: false,
        code: "ADMIN_LOOKUP_FAILED",
        message: rowError.message,
      }),
    };
  }
  if (!row || row.is_active !== true) {
    return {
      ok: false,
      response: jsonResponse(403, {
        ok: false,
        code: "FORBIDDEN_ADMIN",
        message: "Account is not an active admin.",
      }),
    };
  }

  const role = row.role === "superadmin" ? "superadmin" : "admin";
  return { ok: true, userId: authUserId, email: authEmail, role };
}
```

- [ ] **Step 2: Run the test**

Run:
```pwsh
cmd /c "cd admin && npm test"
```
Expected: 6 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add admin/netlify/functions/_shared/admin-user-session.ts admin/netlify/functions/_shared/admin-user-session.test.ts
git commit -m "feat(functions): requireAdminUserSession (shared secret + JWT + allowlist)"
```

---

### Task A3.3: Forward JWT from server actions to functions

**Files:**
- Modify: `admin/src/app/sessions/actions.ts`
- Modify: `admin/src/app/quiz-bank/actions.ts`
- Modify: `admin/src/lib/session-create.ts` (only if the action goes through HTTP — otherwise skip)
- Modify: `admin/src/lib/quiz-write.ts` (same condition)
- Modify: `admin/netlify/functions/_shared/http.ts`

Inspection: the current `sessions/actions.ts` calls `createSessionRecord(parsed)` **directly** (not through HTTP). So the JWT is not in play for the server-action path — it's already enforced by `requireAdminSession()` at the action boundary, and `created_by` is set from the verified session id (A2.7). The JWT verification on Netlify functions only matters when someone hits the function URL **directly** (cron jobs, external scripts, malicious callers).

That means:
- **No change needed to the server actions for JWT forwarding** — they don't call the HTTP endpoint.
- **The Netlify function still needs the JWT gate for non-Next.js callers.** For the Next.js → function path, we keep both the shared secret and (when the function is called from inside Next.js) skip the JWT requirement.

Decision: keep the JWT requirement **mandatory** on the function. Update the Netlify endpoint to accept an in-process bypass: if the request carries a special header `x-medrash-internal-bypass: ${MEDRASH_INTERNAL_BYPASS}` (a third secret), allow it without the JWT, but still require `created_by` to be supplied in the body. This preserves the public-endpoint defense without forcing the Next.js server-action path to mint a service-role JWT.

Updated approach for A3:

- [ ] **Step 1: Update `admin/netlify/functions/_shared/admin-user-session.ts`** to also accept an internal bypass

Modify the top of the function:
```typescript
const internalBypass = process.env.MEDRASH_INTERNAL_BYPASS?.trim();
const presentedBypass = getHeader(event, "x-medrash-internal-bypass").trim();
if (internalBypass && presentedBypass && presentedBypass === internalBypass) {
  // In-process call from the admin Next.js app. created_by must arrive in the
  // body; the caller has already verified the rep via requireAdminSession().
  const bodyCreatedBy =
    (event.body && JSON.parse(event.body)?.createdBy) || null;
  if (!bodyCreatedBy || typeof bodyCreatedBy !== "string") {
    return {
      ok: false,
      response: jsonResponse(400, {
        ok: false,
        code: "MISSING_CREATED_BY",
        message: "Internal calls must include createdBy in the body.",
      }),
    };
  }
  return { ok: true, userId: bodyCreatedBy, email: "", role: "admin" };
}
```

Add tests for the bypass path in `admin-user-session.test.ts`:
```typescript
  it("accepts internal-bypass header + createdBy in body", async () => {
    process.env.MEDRASH_INTERNAL_BYPASS = "internal-secret";
    const event = makeEvent({
      headers: {
        "x-medrash-admin-write-key": "test-write-key",
        "x-medrash-internal-bypass": "internal-secret",
      },
      body: JSON.stringify({ createdBy: "u-internal" }),
    });
    const result = await requireAdminUserSession(event);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.userId).toBe("u-internal");
  });
```

- [ ] **Step 2: Run tests**

Run:
```pwsh
cmd /c "cd admin && npm test"
```
Expected: 7 tests PASS.

---

### Task A3.4: Call `requireAdminUserSession` from write functions

**Files:**
- Modify: `admin/netlify/functions/session-create.ts`
- Modify: `admin/netlify/functions/quiz-bank-write.ts`

- [ ] **Step 1: Update `session-create.ts`**

Replace the body of `handler`:

```typescript
import { jsonResponse, parseJsonBody, requirePost, toV2Handler, HandlerEvent } from "./_shared/http";
import { requireAdminUserSession } from "./_shared/admin-user-session";
import {
  createSessionRecord,
  parseCreateSessionInput,
} from "../../src/lib/session-create";

export async function handler(event: HandlerEvent) {
  const methodGuard = requirePost(event);
  if (methodGuard) return methodGuard;

  const auth = await requireAdminUserSession(event);
  if (!auth.ok) return auth.response;

  let body: Record<string, unknown>;
  try {
    body = parseJsonBody(event);
  } catch (err) {
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_JSON_BODY",
      message: err instanceof Error ? err.message : "Invalid request body.",
    });
  }

  let input;
  try {
    // createdBy is ALWAYS the verified user id, never trusted from the body.
    input = parseCreateSessionInput(body, auth.userId);
  } catch (err) {
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_INPUT",
      message: err instanceof Error ? err.message : "Invalid input.",
    });
  }

  try {
    const result = await createSessionRecord(input);
    return jsonResponse(201, {
      ok: true,
      session: result.session,
      joinUrl: result.joinUrl,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to create session.";
    const isNotFound = /not found/i.test(message);
    const isConflict = /unique join code|inactive quiz/i.test(message);
    return jsonResponse(isNotFound ? 404 : isConflict ? 409 : 500, {
      ok: false,
      code: isNotFound
        ? "QUIZ_NOT_FOUND"
        : isConflict
          ? "SESSION_CONFLICT"
          : "SESSION_CREATE_FAILED",
      message,
    });
  }
}

export default toV2Handler(handler);
```

- [ ] **Step 2: Update `quiz-bank-write.ts`**

Change the `authGuard` block at the top of `handler` from:
```typescript
  const authGuard = requireAdminWriteAuthorization(event);
  if (authGuard) return authGuard;
```
to:
```typescript
  const auth = await requireAdminUserSession(event);
  if (!auth.ok) return auth.response;
```

Then thread `auth.userId` into every parse call: `parseCreateQuizInput(payload!, auth.userId)`, `parseCreateQuestionInput(payload!, auth.userId)`, and `parseUpdateQuizInput(payload!, auth.userId)` (update doesn't carry `created_by`, but parsing the second arg is harmless and keeps the API uniform — or change the signature to accept the second arg only on Create variants and leave Update unchanged).

- [ ] **Step 3: Remove or deprecate `requireAdminWriteAuthorization` import**

If no remaining callers, delete `admin/netlify/functions/_shared/admin-gate.ts`. If something still uses it, keep but mark for removal in Phase A4.

Run:
```pwsh
cmd /c "cd admin && grep -r requireAdminWriteAuthorization admin/netlify"
```
If zero results outside `admin-gate.ts`, delete the file:
```bash
git rm admin/netlify/functions/_shared/admin-gate.ts
```

- [ ] **Step 4: Typecheck + build + test**

```pwsh
cmd /c "cd admin && npm run typecheck"
cmd /c "cd admin && npm run build"
cmd /c "cd admin && npm test"
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add admin/netlify/functions
git commit -m "feat(functions): gate session-create + quiz-bank-write with admin-user-session"
```

---

### Task A3.5: Update the hosted-deploy runbook

**Files:**
- Modify: `docs/hosted-deploy.md`

- [ ] **Step 1: Append a new §2.1 (env vars) row for each new variable**

Add to the env-vars table:

| Variable | Used by | Notes |
| --- | --- | --- |
| `SUPABASE_ANON_KEY` | admin SSR middleware | Public anon key from Supabase Settings → API. Required for the Edge middleware to read sessions. |
| `MEDRASH_INTERNAL_BYPASS` | functions only | Secret enabling Next.js → Netlify-function in-process calls to skip JWT verification. Generate with `openssl rand -hex 32`. Mark **Sensitive**. |

- [ ] **Step 2: Append §1.3 — first superadmin bootstrap**

```
### 1.3 First superadmin

After migrations 001–006 are applied and env vars are set:

  $env:SUPABASE_URL = "https://<ref>.supabase.co"
  $env:SUPABASE_SERVICE_ROLE_KEY = "<service role>"
  $env:ADMIN_BOOTSTRAP_EMAIL = "your-email@yours.com"
  node ./scripts/seed-admin.mjs

Expected: prints user_id, role=superadmin, active=true. After this, sign in
via /login on the deployed admin URL using the magic link delivered by
Resend.
```

- [ ] **Step 3: Append §6 — Resend SMTP setup**

```
## 6. Resend SMTP configuration

1. Create a free Resend account (https://resend.com).
2. In Supabase → Authentication → Email Templates → SMTP Settings:
   - host = smtp.resend.com
   - port = 465
   - user = "resend"
   - pass = Resend API key
   - from = noreply@<resend-shared-domain>
3. Customize the "Magic Link" template subject / body.
4. Trigger one test magic link to your own email; verify delivery <30 s.
5. When a real domain is available, swap the From address and add the DKIM
   CNAMEs Resend provides. Zero code change.
```

- [ ] **Step 4: Remove the `MEDRASH_ADMIN_PORTAL_KEY` row**

Search and delete the existing reference to `MEDRASH_ADMIN_PORTAL_KEY` from the env-vars table — it is no longer used after middleware is replaced.

- [ ] **Step 5: Commit**

```bash
git add docs/hosted-deploy.md
git commit -m "docs(deploy): document Phase A env vars + first-superadmin bootstrap"
```

---

## Final verification

- [ ] **Step 1: Full local checks**

```pwsh
cmd /c "cd admin && npm run lint"
cmd /c "cd admin && npm run typecheck"
cmd /c "cd admin && npm test"
cmd /c "cd admin && npm run build"
```
All four must pass.

- [ ] **Step 2: Manual end-to-end smoke**

1. Run `node ./scripts/seed-admin.mjs` against the dev Supabase project with your email.
2. `cmd /c "cd admin && npm run dev"`.
3. Sign in, land on `/dashboard`. Toggle "All" → "Mine" → list narrows. ✓
4. Create a session → `created_by` populated → reappears under "Mine". ✓
5. `/admin-users` is visible (you're superadmin). Invite a second email (use a `+test` alias if needed). The second magic link arrives. ✓
6. As superadmin, deactivate the second account. Their next page hit bounces to `/denied`. ✓
7. Try `curl -X POST https://<site>/.netlify/functions/session-create` with the shared secret but **no JWT**: expect 401. ✓
8. Document any FAIL in a follow-up todo.

- [ ] **Step 3: Push & open PR**

```bash
git push origin main
```

PR description should list each commit by sub-phase and link to the relevant section of this plan.

---

## Spec coverage self-review

- A0: migration 006 ✓ ; bootstrap script ✓ ; vitest infra ✓ — Spec §2, §4-`scripts/seed-admin.mjs`.
- A1: SSR client ✓ ; allowlist guard ✓ ; new middleware ✓ ; login / callback / signout / denied pages ✓ ; admin-shell user prop ✓ ; sidebar role filter ✓ — Spec §3.1, §3.2, §3.3, §4.
- A2: admin_users page + actions ✓ ; superadmin-only enforcement ✓ ; self-deactivation block ✓ ; zero-superadmin invariant ✓ ; default-mine ScopeToggle on dashboard/sessions/quiz-bank ✓ ; `created_by` plumbed into both server-action insert paths ✓ — Spec §3.3, §5, change-3.
- A3: shared-secret + JWT + allowlist gate for Netlify writes ✓ ; in-process bypass for Next.js → function path ✓ ; vitest tests ✓ — Spec §1 architecture, §4, change-2.
- Resend SMTP + first-superadmin bootstrap documented in runbook ✓ — Spec §6.
- Out of scope intentionally: reports/intelligence scope toggle (RPCs don't carry `created_by` yet — defer to Phase A4); true global sign-out; OTP fallback; remember-me — matches cut-line §8.

No placeholders. No "TBD". Type names consistent (`AdminSession`, `AdminRole`, `Scope`, `ListScope`). Method signatures match call sites across tasks.
