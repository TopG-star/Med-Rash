import Link from "next/link";
import { redirect } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";
import { readMfaStatus } from "@/lib/admin-mfa-server";

import { DisableMfaForm } from "./disable-mfa-form";

export const dynamic = "force-dynamic";
export const revalidate = 0;

/**
 * Owner-only account security surface. For now the only management action
 * is "Disable MFA" — the server helper (`disableMfaAction`) has existed since
 * MFA shipped but had no UI. Routes for Hosts (who have no MFA requirement)
 * bounce to the dashboard.
 */
export default async function AccountSecurityPage() {
  const session = await requireAdminSession({
    currentPath: "/account/security",
  });
  if (session.role !== "owner") {
    redirect("/dashboard");
  }

  const status = await readMfaStatus();
  if (!status) {
    redirect("/login");
  }

  const isAal2 = status.currentLevel === "aal2";
  const isEnrolled = status.hasVerifiedFactor;

  return (
    <AdminShell
      title="Account Security"
      subtitle="Manage your two-factor authentication and signed-in sessions."
      titleSize="sm"
      user={{ email: session.email, role: session.role }}
      actions={
        <span className="vp-scope">
          <Link href="/dashboard" className="vp-button vp-button-secondary">
            Back to Dashboard
          </Link>
        </span>
      }
    >
      <div className="vp-scope vp-vstack vp-vstack-lg">
        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Two-factor authentication</h2>
          </div>
          <div className="vp-vstack vp-vstack-md">
            <div className="vp-meta-row">
              <span>
                Status ·{" "}
                <strong>
                  {isEnrolled ? "Enrolled" : "Not enrolled"}
                </strong>
              </span>
              <span>
                Current session AAL ·{" "}
                <strong>{status.currentLevel ?? "unknown"}</strong>
              </span>
            </div>

            {!isEnrolled ? (
              <p className="vp-banner vp-banner-info">
                You haven&apos;t enrolled an authenticator yet. Go to{" "}
                <Link className="vp-link" href="/onboarding/mfa">
                  /onboarding/mfa
                </Link>{" "}
                to set one up.
              </p>
            ) : isAal2 ? (
              <DisableMfaForm />
            ) : (
              <div className="vp-vstack vp-vstack-sm">
                <p className="vp-banner vp-banner-info">
                  Re-verify your authenticator before disabling MFA. This
                  ensures the request is coming from someone holding the
                  current second factor.
                </p>
                <div>
                  <Link
                    href="/onboarding/mfa?next=/account/security"
                    className="vp-button vp-button-primary"
                  >
                    Re-verify now
                  </Link>
                </div>
              </div>
            )}
          </div>
        </section>
      </div>
    </AdminShell>
  );
}
