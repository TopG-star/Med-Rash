import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/admin-session";
import { readMfaStatus } from "@/lib/admin-mfa-server";

import { EnrollSection } from "./enroll-form";
import { ChallengeSection } from "./challenge-form";
import { safeNext } from "./state";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function MfaPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const session = await requireAdminSession({ currentPath: "/onboarding/mfa" });
  if (session.role !== "owner") {
    // Hosts have no MFA requirement; bounce them off the page.
    redirect("/dashboard");
  }
  const params = await searchParams;
  const next = safeNext(params.next);

  const status = await readMfaStatus();
  if (!status) {
    // Session was good 50ms ago — race or transient — bounce to login.
    redirect("/login");
  }

  // Already AAL2 (e.g. they came back via bookmark) — send them where
  // they were trying to go.
  if (status.currentLevel === "aal2") {
    redirect(next);
  }

  return (
    <main className="vp-auth">
      <div className="vp-stack">
        <div className="vp-hero">
          <p className="vp-eyebrow">MedRash Admin</p>
          <h1 className="vp-display">
            Two-factor <span className="vp-display-accent">authentication</span>
          </h1>
          <p className="vp-tagline">
            Owner accounts are required to confirm a second factor on every
            session. Use any TOTP app (Google Authenticator, 1Password, Authy).
          </p>
        </div>
        {status.hasVerifiedFactor ? (
          <ChallengeSection email={session.email} next={next} />
        ) : (
          <EnrollSection email={session.email} next={next} />
        )}
      </div>
    </main>
  );
}
