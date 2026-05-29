"use server";

import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/admin-session";
import { logAdminAction } from "@/lib/audit";
import { getAdminSupabaseClient } from "@/lib/supabase-server";
import {
  JOB_ROLES,
  type JobRole,
  type OnboardingActionState,
} from "./state";

function isJobRole(value: string): value is JobRole {
  return (JOB_ROLES as readonly string[]).includes(value);
}

export async function completeOnboardingAction(
  _prev: OnboardingActionState,
  formData: FormData,
): Promise<OnboardingActionState> {
  // Guard A: the user identity comes ONLY from the session cookie, never
  // from form input. We don't even read an email field — the WHERE clause
  // below pins the update to session.userId.
  const session = await requireAdminSession({ currentPath: "/onboarding" });

  const fullName =
    typeof formData.get("full_name") === "string"
      ? (formData.get("full_name") as string).trim()
      : "";
  const company =
    typeof formData.get("company") === "string"
      ? (formData.get("company") as string).trim()
      : "";
  const jobRoleRaw =
    typeof formData.get("job_role") === "string"
      ? (formData.get("job_role") as string).trim()
      : "";

  if (fullName.length < 2 || fullName.length > 120) {
    return { status: "error", message: "Enter your full name (2–120 characters)." };
  }
  if (company.length < 2 || company.length > 120) {
    return { status: "error", message: "Enter your company (2–120 characters)." };
  }
  if (!isJobRole(jobRoleRaw)) {
    return { status: "error", message: "Pick a job role (MSR or Manager)." };
  }

  const supabase = getAdminSupabaseClient();

  // Re-read the row to make sure a deactivated user can't sneak through by
  // POSTing directly while we render the page for an invited/verified user.
  const { data: current, error: readError } = await supabase
    .from("admin_users")
    .select("status")
    .eq("user_id", session.userId)
    .maybeSingle();

  if (readError) {
    console.error("[onboarding] read failed", readError);
    return { status: "error", message: "Could not save. Try again." };
  }
  if (!current) {
    return { status: "error", message: "Your account is no longer on the allowlist." };
  }
  if (current.status === "deactivated") {
    redirect("/denied?reason=inactive");
  }

  const { error: updateError } = await supabase
    .from("admin_users")
    .update({
      full_name: fullName,
      company,
      job_role: jobRoleRaw,
      status: "active",
    })
    .eq("user_id", session.userId)
    .neq("status", "deactivated");

  if (updateError) {
    console.error("[onboarding] update failed", updateError);
    return { status: "error", message: "Could not save. Try again." };
  }

  void logAdminAction(supabase, {
    actorUserId: session.userId,
    actorRole: session.role,
    action: "complete_onboarding",
    targetType: "admin_user",
    targetId: session.userId,
    payload: { fullName, company, jobRole: jobRoleRaw },
  });
  redirect("/dashboard");
}
