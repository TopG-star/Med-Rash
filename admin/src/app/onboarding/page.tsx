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
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-6 px-6 py-12">
      <header className="space-y-2">
        <p className="text-xs font-extrabold uppercase tracking-[0.15em] text-[var(--arena-ink-muted)]">
          MedRash Admin
        </p>
        <h1 className="font-[family-name:var(--font-anybody)] text-4xl font-extrabold tracking-tight">
          Finish your profile
        </h1>
        <p className="text-sm text-[var(--arena-ink-muted)]">
          Tell us who you are. You only do this once — afterwards you go
          straight to the dashboard.
        </p>
      </header>
      <OnboardingForm
        email={session.email}
        defaultFullName={typeof data.full_name === "string" ? data.full_name : ""}
        defaultCompany={typeof data.company === "string" ? data.company : ""}
        defaultJobRole={asJobRole(data.job_role)}
      />
    </main>
  );
}
