import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type AdminStatus = "invited" | "verified" | "active" | "deactivated";
export type JobRole = "MSR" | "Manager";

export type AdminUserRow = {
  userId: string;
  email: string;
  role: "host" | "owner";
  isActive: boolean;
  status: AdminStatus;
  fullName: string | null;
  company: string | null;
  jobRole: JobRole | null;
  invitedBy: string | null;
  invitedAt: string | null;
  createdAt: string;
};

const COLUMNS =
  "user_id, email, role, is_active, status, full_name, company, job_role, invited_by, invited_at, created_at";

const STATUSES: ReadonlySet<AdminStatus> = new Set<AdminStatus>([
  "invited",
  "verified",
  "active",
  "deactivated",
]);

function normalizeStatus(value: unknown, isActive: boolean): AdminStatus {
  // is_active=false is the legacy kill switch — honor it even if the
  // lifecycle column says otherwise. Otherwise trust the column, falling
  // back to "invited" for unknown values.
  if (!isActive) return "deactivated";
  if (typeof value === "string" && STATUSES.has(value as AdminStatus)) {
    return value as AdminStatus;
  }
  return "invited";
}

function normalizeJobRole(value: unknown): JobRole | null {
  return value === "MSR" || value === "Manager" ? value : null;
}

function mapRow(row: Record<string, unknown>): AdminUserRow {
  const role = row.role === "owner" ? "owner" : "host";
  const isActive = row.is_active === true;
  return {
    userId: String(row.user_id),
    email: String(row.email),
    role,
    isActive,
    status: normalizeStatus(row.status, isActive),
    fullName: typeof row.full_name === "string" && row.full_name ? row.full_name : null,
    company: typeof row.company === "string" && row.company ? row.company : null,
    jobRole: normalizeJobRole(row.job_role),
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
