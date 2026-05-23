"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@supabase/supabase-js";

import { requireAdminSession } from "@/lib/admin-session";
import { getAdminSupabaseClient } from "@/lib/supabase-server";

export type AdminUsersActionResult =
  | { ok: true; message: string }
  | { ok: false; message: string };

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function fail(message: string): { ok: false; message: string } {
  return { ok: false, message };
}

async function requireOwner() {
  const session = await requireAdminSession({ currentPath: "/admin-users" });
  if (session.role !== "owner") {
    throw new Error("FORBIDDEN_OWNER_ONLY");
  }
  return session;
}

async function isLastActiveOwner(userId: string): Promise<boolean> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("admin_users")
    .select("user_id")
    .eq("role", "owner")
    .eq("is_active", true);
  if (error) throw new Error(error.message);
  const owners = (data ?? []).map((r) => r.user_id);
  return owners.length <= 1 && owners.includes(userId);
}

/**
 * Build a Supabase client capable of calling auth.admin.* (service-role).
 * Reuses the shared service-role url + key but constructs a fresh client
 * because the cached `getAdminSupabaseClient` is pinned to schema "app",
 * and auth.admin.* lives in the `auth` schema.
 */
function getAuthAdminClient() {
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!url) throw new Error("SUPABASE_URL is not configured.");
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured.");
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function getInviteRedirect(): string {
  const base =
    process.env.MEDRASH_ADMIN_PORTAL_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_SITE_URL?.trim();
  if (!base) {
    throw new Error(
      "MEDRASH_ADMIN_PORTAL_BASE_URL (or NEXT_PUBLIC_SITE_URL) must be set to invite admins.",
    );
  }
  return `${base.replace(/\/$/, "")}/auth/callback`;
}

export async function inviteAdminAction(
  raw: Record<string, unknown>,
): Promise<AdminUsersActionResult> {
  let session;
  try {
    session = await requireOwner();
  } catch (err) {
    return fail(
      err instanceof Error && err.message === "FORBIDDEN_OWNER_ONLY"
        ? "Only Owners can invite teammates."
        : err instanceof Error
          ? err.message
          : "Authorization failed.",
    );
  }

  const emailRaw = raw.email;
  const roleRaw = raw.role;
  const email = typeof emailRaw === "string" ? emailRaw.trim().toLowerCase() : "";
  const role: "host" | "owner" =
    roleRaw === "owner" ? "owner" : "host";

  if (!EMAIL_RE.test(email)) return fail("Enter a valid email address.");

  let redirectTo: string;
  try {
    redirectTo = getInviteRedirect();
  } catch (err) {
    return fail(err instanceof Error ? err.message : "Redirect not configured.");
  }

  try {
    const authClient = getAuthAdminClient();
    const inviteResult = await authClient.auth.admin.inviteUserByEmail(email, {
      redirectTo,
    });

    // If the user already exists in Supabase auth, look them up so we can
    // upsert the admin_users row anyway.
    let userId: string | null = inviteResult.data?.user?.id ?? null;
    if (!userId) {
      const { data: list, error: listError } =
        await authClient.auth.admin.listUsers({ page: 1, perPage: 200 });
      if (listError) {
        return fail(`Lookup failed after invite: ${listError.message}`);
      }
      const match = list.users.find(
        (u) => (u.email ?? "").toLowerCase() === email,
      );
      userId = match?.id ?? null;
    }
    if (!userId) {
      return fail(
        "Invite sent but Supabase did not return a user id; check Supabase auth logs.",
      );
    }

    const supabase = getAdminSupabaseClient();
    const { error: upsertError } = await supabase
      .from("admin_users")
      .upsert(
        {
          user_id: userId,
          email,
          role,
          is_active: true,
          invited_by: session.userId,
          invited_at: new Date().toISOString(),
        },
        { onConflict: "user_id" },
      );
    if (upsertError) {
      return fail(`Failed to record admin row: ${upsertError.message}`);
    }

    revalidatePath("/admin-users");
    return { ok: true, message: `Invitation sent to ${email}.` };
  } catch (err) {
    return fail(
      err instanceof Error ? err.message : "Invite failed unexpectedly.",
    );
  }
}

async function setActive(
  userId: string,
  active: boolean,
): Promise<AdminUsersActionResult> {
  let session;
  try {
    session = await requireOwner();
  } catch (err) {
    return fail(
      err instanceof Error && err.message === "FORBIDDEN_OWNER_ONLY"
        ? "Only Owners can change teammate status."
        : err instanceof Error
          ? err.message
          : "Authorization failed.",
    );
  }
  if (!userId) return fail("userId is required.");
  if (userId === session.userId) {
    return fail("You can't change your own status. Ask another Owner.");
  }
  if (!active && (await isLastActiveOwner(userId))) {
    return fail("Can't deactivate the last active Owner. Promote someone first.");
  }

  const supabase = getAdminSupabaseClient();
  const { error } = await supabase
    .from("admin_users")
    .update({ is_active: active })
    .eq("user_id", userId);
  if (error) return fail(error.message);

  revalidatePath("/admin-users");
  return {
    ok: true,
    message: active ? "Teammate reactivated." : "Teammate deactivated.",
  };
}

export async function deactivateAdminAction(
  userId: string,
): Promise<AdminUsersActionResult> {
  return setActive(userId, false);
}

export async function reactivateAdminAction(
  userId: string,
): Promise<AdminUsersActionResult> {
  return setActive(userId, true);
}

export async function setRoleAction(
  userId: string,
  role: "host" | "owner",
): Promise<AdminUsersActionResult> {
  let session;
  try {
    session = await requireOwner();
  } catch (err) {
    return fail(
      err instanceof Error && err.message === "FORBIDDEN_OWNER_ONLY"
        ? "Only Owners can change roles."
        : err instanceof Error
          ? err.message
          : "Authorization failed.",
    );
  }
  if (!userId) return fail("userId is required.");
  if (role !== "host" && role !== "owner")
    return fail("role must be host or owner.");
  if (userId === session.userId) {
    return fail("You can't change your own role. Ask another Owner.");
  }
  if (role === "host" && (await isLastActiveOwner(userId))) {
    return fail("Can't demote the last active Owner. Promote someone first.");
  }

  const supabase = getAdminSupabaseClient();
  const { error } = await supabase
    .from("admin_users")
    .update({ role })
    .eq("user_id", userId);
  if (error) return fail(error.message);

  revalidatePath("/admin-users");
  return { ok: true, message: `Role updated to ${role}.` };
}
