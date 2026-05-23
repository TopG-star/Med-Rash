import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type AdminUserRow = {
  userId: string;
  email: string;
  role: "host" | "owner";
  isActive: boolean;
  invitedBy: string | null;
  invitedAt: string | null;
  createdAt: string;
};

const COLUMNS =
  "user_id, email, role, is_active, invited_by, invited_at, created_at";

function mapRow(row: Record<string, unknown>): AdminUserRow {
  const role = row.role === "owner" ? "owner" : "host";
  return {
    userId: String(row.user_id),
    email: String(row.email),
    role,
    isActive: row.is_active === true,
    invitedBy: row.invited_by ? String(row.invited_by) : null,
    invitedAt: row.invited_at ? String(row.invited_at) : null,
    createdAt: String(row.created_at),
  };
}

export async function listAdminUsers(): Promise<AdminUserRow[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("admin_users")
    .select(COLUMNS)
    .order("created_at", { ascending: false });
  if (error) throw new Error(`Failed to list admin users: ${error.message}`);
  return (data ?? []).map((r) => mapRow(r as Record<string, unknown>));
}

export async function getAdminUserByEmail(
  email: string,
): Promise<AdminUserRow | null> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("admin_users")
    .select(COLUMNS)
    .eq("email", email)
    .maybeSingle();
  if (error) throw new Error(`Failed to look up admin user: ${error.message}`);
  return data ? mapRow(data as Record<string, unknown>) : null;
}
