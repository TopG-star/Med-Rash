import "server-only";

import { redirect } from "next/navigation";

import { getAdminSupabaseClient } from "./supabase-server";
import { getServerSupabaseClient } from "./supabase-ssr";

export type AdminRole = "host" | "owner";

export type AdminSession = {
  userId: string;
  email: string;
  role: AdminRole;
};

/**
 * Resolve the current request's admin session by checking:
 *   1. Supabase has a signed-in user via cookies, and
 *   2. That user has an active row in app.admin_users.
 *
 * Returns null when either check fails. Use {@link requireAdminSession} to
 * redirect unauthenticated requests to /login and unallowlisted ones to /denied.
 */
export async function getAdminSession(): Promise<AdminSession | null> {
  const supabase = await getServerSupabaseClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;

  const userId = data.user.id;
  const email = data.user.email ?? null;
  if (!email) return null;

  // We read app.admin_users via the service-role client so a stale or
  // mis-scoped RLS policy can't make the allowlist look empty.
  const service = getAdminSupabaseClient();
  const { data: row, error: lookupError } = await service
    .from("admin_users")
    .select("user_id, email, role, is_active")
    .eq("user_id", userId)
    .maybeSingle();

  if (lookupError) {
    console.error("[admin-session] admin_users lookup failed", lookupError);
    return null;
  }
  if (!row || row.is_active !== true) return null;

  const role: AdminRole = row.role === "owner" ? "owner" : "host";
  return { userId, email, role };
}

/**
 * Server Component / Server Action guard. Returns a non-null AdminSession
 * or redirects:
 *   - to /login?next=<currentPath> when there is no Supabase user, or
 *   - to /denied                    when the user is not on the allowlist.
 *
 * `currentPath` is required because Next does not expose the request URL
 * inside Server Components. Pass it from the page (e.g. usePathname is
 * not server-safe; use the page's static route).
 */
export async function requireAdminSession(
  options: { currentPath?: string } = {},
): Promise<AdminSession> {
  const supabase = await getServerSupabaseClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    const next = options.currentPath ?? "/dashboard";
    redirect(`/login?next=${encodeURIComponent(next)}`);
  }

  const session = await getAdminSession();
  if (!session) {
    redirect("/denied");
  }
  return session;
}

/**
 * Server Component / Server Action / Route Handler guard for Owner-only
 * surfaces (quiz bank, reports, intelligence, team management). Behaves
 * like {@link requireAdminSession} but additionally redirects hosts to
 * `/denied?reason=role`. Hosts must never reach owner-only data — hiding
 * the nav link is not enough, the page itself must reject them.
 */
export async function requireOwner(
  options: { currentPath?: string } = {},
): Promise<AdminSession> {
  const session = await requireAdminSession(options);
  if (session.role !== "owner") {
    redirect("/denied?reason=role");
  }
  return session;
}
