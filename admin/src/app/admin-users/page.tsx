import { AdminShell } from "@/components/admin-shell";
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

const STATUS_LABELS: Record<AdminStatus, string> = {
  invited: "invited",
  verified: "verified",
  active: "active",
  deactivated: "deactivated",
};

function StatusPill({ status }: { status: AdminStatus }) {
  return (
    <span className={`vp-status-pill is-${status}`}>{STATUS_LABELS[status]}</span>
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
      <div className="vp-scope vp-vstack vp-vstack-lg">
        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Invite Teammate</h2>
          </div>
          <p className="vp-panel-helper">
            Send invite emails and assign the initial access role. Only Owners can
            manage team seats.
          </p>
          <InviteForm />
        </section>

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Current Team</h2>
          </div>
          {loadError ? (
            <p role="alert" className="vp-banner vp-banner-error">{loadError}</p>
          ) : rows.length === 0 ? (
            <div className="vp-empty">
              <div aria-hidden="true" className="vp-empty-icon">TM</div>
              <h3 className="vp-empty-title">No team members yet</h3>
              <p className="vp-empty-helper">
                Run the seed script or invite someone above.
              </p>
            </div>
          ) : (
            <div className="vp-table-wrap">
              <table className="vp-table">
                <caption className="vp-sr-only">
                  Team members with roles, access status, invite timestamps, and management actions.
                </caption>
                <thead>
                  <tr>
                    <th scope="col">Teammate</th>
                    <th scope="col">Role</th>
                    <th scope="col">Status</th>
                    <th scope="col">Invited</th>
                    <th scope="col">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => {
                    const isSelf = r.userId === session.userId;
                    const profileBits = [r.fullName, r.company, r.jobRole]
                      .filter((v): v is string => Boolean(v))
                      .join(" · ");
                    return (
                      <tr key={r.userId}>
                        <td>
                          <div className="vp-team-user-line">
                            <span className="vp-row-label-strong">{r.email}</span>
                            {isSelf ? (
                              <span className="vp-tag vp-team-self-pill">you</span>
                            ) : null}
                          </div>
                          {profileBits ? (
                            <div className="vp-team-profile">{profileBits}</div>
                          ) : null}
                        </td>
                        <td>
                          <span className="vp-team-role">{r.role}</span>
                        </td>
                        <td>
                          <StatusPill status={r.status} />
                        </td>
                        <td className="is-muted">
                          {formatDate(r.invitedAt ?? r.createdAt)}
                        </td>
                        <td className="vp-team-actions-cell">
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
        </section>
      </div>
    </AdminShell>
  );
}
