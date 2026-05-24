import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";
import { requireOwner } from "@/lib/admin-session";
import {
  listAdminUsers,
  type AdminStatus,
} from "@/lib/admin-users-queries";

import { AdminRowActions } from "./admin-row-actions";
import { InviteForm } from "./invite-form";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function formatDate(value: string | null): string {
  if (!value) return "—";
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) return value;
  return new Date(ms).toLocaleString();
}

const STATUS_STYLES: Record<AdminStatus, { bg: string; label: string }> = {
  invited: { bg: "bg-amber-200 text-amber-900", label: "invited" },
  verified: { bg: "bg-sky-200 text-sky-900", label: "verified" },
  active: { bg: "bg-emerald-200 text-emerald-900", label: "active" },
  deactivated: { bg: "bg-stone-300 text-stone-700", label: "deactivated" },
};

function StatusPill({ status }: { status: AdminStatus }) {
  const style = STATUS_STYLES[status];
  return (
    <span
      className={`inline-flex rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.05em] ${style.bg}`}
    >
      {style.label}
    </span>
  );
}

export default async function AdminUsersPage() {
  const session = await requireOwner({ currentPath: "/admin-users" });

  let rows: Awaited<ReturnType<typeof listAdminUsers>> = [];
  let loadError: string | null = null;
  try {
    rows = await listAdminUsers();
  } catch (err) {
    loadError = err instanceof Error ? err.message : "Failed to load admins.";
  }

  return (
    <AdminShell
      title="Team"
      subtitle="Invite teammates, manage roles, and revoke access. Only Owners can see this page."
      user={{ email: session.email, role: session.role }}
    >
      <PanelCard title="Invite Teammate">
        <InviteForm />
      </PanelCard>

      <PanelCard title="Current Team">
        {loadError ? (
          <p className="text-sm font-semibold text-[var(--arena-danger)]">
            {loadError}
          </p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-[var(--arena-ink-muted)]">
            No team members yet. Run the seed script or invite someone above.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--arena-ink-muted)]">
                  <th className="py-2 pr-4">Teammate</th>
                  <th className="py-2 pr-4">Role</th>
                  <th className="py-2 pr-4">Status</th>
                  <th className="py-2 pr-4">Invited</th>
                  <th className="py-2 pr-4">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const isSelf = r.userId === session.userId;
                  const profileBits = [r.fullName, r.company, r.jobRole]
                    .filter((v): v is string => Boolean(v))
                    .join(" · ");
                  return (
                    <tr
                      key={r.userId}
                      className="border-t-[2px] border-[var(--arena-outline-muted)]"
                    >
                      <td className="py-3 pr-4">
                        <div className="font-medium">
                          {r.email}
                          {isSelf ? (
                            <span className="ml-2 rounded-full bg-[var(--arena-secondary)] px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.05em]">
                              you
                            </span>
                          ) : null}
                        </div>
                        {profileBits ? (
                          <div className="text-xs text-[var(--arena-ink-muted)]">
                            {profileBits}
                          </div>
                        ) : null}
                      </td>
                      <td className="py-3 pr-4 font-semibold uppercase tracking-[0.05em]">
                        {r.role}
                      </td>
                      <td className="py-3 pr-4">
                        <StatusPill status={r.status} />
                      </td>
                      <td className="py-3 pr-4 text-[var(--arena-ink-muted)]">
                        {formatDate(r.invitedAt ?? r.createdAt)}
                      </td>
                      <td className="py-3 pr-4">
                        <AdminRowActions
                          userId={r.userId}
                          role={r.role}
                          isActive={r.isActive}
                          status={r.status}
                          isSelf={isSelf}
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </PanelCard>
    </AdminShell>
  );
}
