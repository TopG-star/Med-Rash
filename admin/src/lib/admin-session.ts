import "server-only";

import { headers } from "next/headers";
import { redirect } from "next/navigation";

import { logAuthEvent } from "./audit";
import { getAdminSupabaseClient } from "./supabase-server";
import { getServerSupabaseClient } from "./supabase-ssr";

export type AdminRole = "host" | "owner";

/**
 * Slice B1 P2 — paths the owner is allowed to reach without AAL2.
 * Adding anything to this allowlist intentionally widens the hard-block,
 * so keep it tiny: the MFA enrollment/challenge surface itself, the
 * signout route, and the /denied page (so a misconfigured user can read
 * what went wrong without bouncing).
 */
const OWNER_AAL2_EXEMPT_PREFIXES = [
  "/onboarding/mfa",
  "/auth/signout",
  "/denied",
];

function isOwnerAal2Exempt(path: string): boolean {
  return OWNER_AAL2_EXEMPT_PREFIXES.some((p) => path === p || path.startsWith(`${p}/`) || path.startsWith(`${p}?`));
}

export type AdminSession = {
  userId: string;
  email: string;
  role: AdminRole;
};

async function readClientHeaders(): Promise<{
  ip: string | null;
  userAgent: string | null;
}> {
  try {
    const h = await headers();
    const xff = h.get("x-forwarded-for");
    const ip = xff ? (xff.split(",")[0]?.trim() ?? null) : null;
    const userAgent = h.get("user-agent");
    return { ip, userAgent };
  } catch {
    return { ip: null, userAgent: null };
  }
}

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
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(service, {
      eventType: "allowlist_deny",
      userId,
      email,
      ip,
      userAgent,
      result: "lookup_error",
      metadata: { error: lookupError.message },
    });
    return null;
  }
  if (!row || row.is_active !== true) {
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(service, {
      eventType: "allowlist_deny",
      userId,
      email,
      ip,
      userAgent,
      result: row ? "inactive" : "not_on_allowlist",
    });
    return null;
  }

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

  // Slice B1 P2 — owner-role hard-block on AAL2. Any owner request that
  // is not on the small enrollment/signout/denied allowlist must hold an
  // AAL2 session OR be redirected to /onboarding/mfa to either enroll
  // (first time) or pass a challenge (factor exists, current session is
  // AAL1 because they only completed the email OTP step). Hosts are
  // unaffected — TOTP is owner-only per the plan.
  const currentPath = options.currentPath ?? "/dashboard";
  if (session.role === "owner" && !isOwnerAal2Exempt(currentPath)) {
    const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aalData?.currentLevel !== "aal2") {
      redirect(`/onboarding/mfa?next=${encodeURIComponent(currentPath)}`);
    }
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
