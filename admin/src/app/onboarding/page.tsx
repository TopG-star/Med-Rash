import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/admin-session";
import { getAdminSupabaseClient } from "@/lib/supabase-server";

import { OnboardingForm } from "./onboarding-form";
import { JOB_ROLES, type JobRole } from "./state";

export const dynamic = "force-dynamic";

function asJobRole(value: unknown): JobRole | "" {
  if (typeof value !== "string") return "";
  return (JOB_ROLES as readonly string[]).includes(value)
    ? (value as JobRole)
    : "";
}

export default async function OnboardingPage() {
  const session = await requireAdminSession({ currentPath: "/onboarding" });

  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("admin_users")
    .select("status, full_name, company, job_role")
    .eq("user_id", session.userId)
    .maybeSingle();

  if (error) {
    console.error("[onboarding] lookup failed", error);
    redirect("/denied?reason=config");
  }
  if (!data) {
    redirect("/denied");
  }

  if (data.status === "active") {
    redirect("/dashboard");
  }
  if (data.status === "deactivated") {
    redirect("/denied?reason=inactive");
  }

  return (
    <main className="vp-auth">
      <div className="vp-stack">
        <div className="vp-hero">
          <span aria-hidden className="vp-logo-tile">
            <svg
              width="32"
              height="32"
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M12 2 4 5v6c0 5 3.5 9.4 8 11 4.5-1.6 8-6 8-11V5l-8-3Z"
                fill="currentColor"
                fillOpacity="0.18"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinejoin="round"
              />
              <path
                d="m8.5 12 2.5 2.5L15.5 10"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </span>
          <p className="vp-eyebrow">MedRash Admin</p>
          <h1 className="vp-display">
            Finish your <span className="vp-display-accent">profile</span>
          </h1>
          <p className="vp-tagline">
            Tell us who you are. You only do this once — afterwards you go
            straight to the dashboard.
          </p>
        </div>
        <OnboardingForm
          email={session.email}
          defaultFullName={typeof data.full_name === "string" ? data.full_name : ""}
          defaultCompany={typeof data.company === "string" ? data.company : ""}
          defaultJobRole={asJobRole(data.job_role)}
        />
      </div>
    </main>
  );
}
