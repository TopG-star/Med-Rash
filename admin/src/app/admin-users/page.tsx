import { redirect } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";
import { requireAdminSession } from "@/lib/admin-session";
import { listAdminUsers } from "@/lib/admin-users-queries";

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

export default async function AdminUsersPage() {
  const session = await requireAdminSession({ currentPath: "/admin-users" });
  if (session.role !== "superadmin") {
    redirect("/denied?reason=role");
  }

  let rows: Awaited<ReturnType<typeof listAdminUsers>> = [];
  let loadError: string | null = null;
  try {
    rows = await listAdminUsers();
  } catch (err) {
    loadError = err instanceof Error ? err.message : "Failed to load admins.";
  }

  return (
    <AdminShell
      title="Admin Users"
      subtitle="Invite teammates, manage roles, and revoke access. Only superadmins can see this page."
      user={{ email: session.email, role: session.role }}
    >
      <PanelCard title="Invite Admin">
        <InviteForm />
      </PanelCard>

      <PanelCard title="Current Admins">
        {loadError ? (
          <p className="text-sm font-semibold text-[var(--arena-danger)]">
            {loadError}
          </p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-[var(--arena-ink-muted)]">
            No admin rows yet. Run the seed script or invite someone above.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--arena-ink-muted)]">
                  <th className="py-2 pr-4">Email</th>
                  <th className="py-2 pr-4">Role</th>
                  <th className="py-2 pr-4">Status</th>
                  <th className="py-2 pr-4">Invited</th>
                  <th className="py-2 pr-4">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const isSelf = r.userId === session.userId;
                  return (
                    <tr
                      key={r.userId}
                      className="border-t-[2px] border-[var(--arena-outline-muted)]"
                    >
                      <td className="py-3 pr-4 font-medium">
                        {r.email}
                        {isSelf ? (
                          <span className="ml-2 rounded-full bg-[var(--arena-secondary)] px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.05em]">
                            you
                          </span>
                        ) : null}
                      </td>
                      <td className="py-3 pr-4 font-semibold uppercase tracking-[0.05em]">
                        {r.role}
                      </td>
                      <td className="py-3 pr-4">
                        {r.isActive ? (
                          <span className="font-semibold">active</span>
                        ) : (
                          <span className="font-semibold text-[var(--arena-danger)]">
                            inactive
                          </span>
                        )}
                      </td>
                      <td className="py-3 pr-4 text-[var(--arena-ink-muted)]">
                        {formatDate(r.invitedAt ?? r.createdAt)}
                      </td>
                      <td className="py-3 pr-4">
                        <AdminRowActions
                          userId={r.userId}
                          email={r.email}
                          role={r.role}
                          isActive={r.isActive}
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
