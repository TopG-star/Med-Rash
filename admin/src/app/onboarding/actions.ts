"use server";

import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/admin-session";
import { logAdminAction } from "@/lib/audit";
import { validateForAction } from "@/lib/schemas/_helpers";
import { completeOnboardingSchema } from "@/lib/schemas/onboarding";
import { getAdminSupabaseClient } from "@/lib/supabase-server";
import { type OnboardingActionState } from "./state";

export async function completeOnboardingAction(
  _prev: OnboardingActionState,
  formData: FormData,
): Promise<OnboardingActionState> {
  // Guard A: the user identity comes ONLY from the session cookie, never
  // from form input. We don't even read an email field — the WHERE clause
  // below pins the update to session.userId.
  const session = await requireAdminSession({ currentPath: "/onboarding" });

  const validated = validateForAction(completeOnboardingSchema, {
    fullName: formData.get("full_name"),
    company: formData.get("company"),
    jobRole: formData.get("job_role"),
  });
  if (!validated.ok) {
    // Preserve original UX-friendly messages by mapping the failing path
    // to the matching string used pre-A7.
    const path = validated.issues[0]?.path ?? "";
    const message =
      path === "fullName"
        ? "Enter your full name (2–120 characters)."
        : path === "company"
          ? "Enter your company (2–120 characters)."
          : path === "jobRole"
            ? "Pick a job role (MSR or Manager)."
            : validated.message;
    return { status: "error", message };
  }
  const { fullName, company, jobRole } = validated.data;

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
      job_role: jobRole,
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
    payload: { fullName, company, jobRole },
  });
  redirect("/dashboard");
}
