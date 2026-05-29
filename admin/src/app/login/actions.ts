"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";

import { logAuthEvent } from "@/lib/audit";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
  resetRateLimit,
} from "@/lib/rate-limit";
import { validateForAction } from "@/lib/schemas/_helpers";
import {
  loginRequestOtpSchema,
  loginVerifyOtpSchema,
} from "@/lib/schemas/identity";
import { getAdminSupabaseClient } from "@/lib/supabase-server";
import { getServerSupabaseClient } from "@/lib/supabase-ssr";
import type { LoginActionState } from "./state";

async function readClientHeaders(): Promise<{
  ip: string | null;
  userAgent: string | null;
}> {
  try {
    const h = await headers();
    const xff = h.get("x-forwarded-for");
    const ip = xff ? (xff.split(",")[0]?.trim() ?? null) : null;
    const userAgent = h.get("user-agent");
    return { ip, userAgent };
  } catch {
    return { ip: null, userAgent: null };
  }
}

const RESEND_COOLDOWN_MS = 60_000;

function safeNext(raw: unknown): string {
  return typeof raw === "string" && raw.startsWith("/") ? raw : "/dashboard";
}

function getPortalBaseUrl(): string | null {
  return (
    process.env.MEDRASH_ADMIN_PORTAL_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_SITE_URL?.trim() ||
    null
  );
}

export async function requestOtpAction(
  _prev: LoginActionState,
  formData: FormData,
): Promise<LoginActionState> {
  const rawEmail = formData.get("email");
  const next = safeNext(formData.get("next"));
  const validated = validateForAction(loginRequestOtpSchema, {
    email: rawEmail,
    next,
  });
  if (!validated.ok) {
    return { status: "error", message: "Enter a valid work email.", next };
  }
  const email = validated.data.email;

  const portalBaseUrl = getPortalBaseUrl();
  if (!portalBaseUrl) {
    return {
      status: "error",
      message:
        "Server is missing MEDRASH_ADMIN_PORTAL_BASE_URL — set it to the deployed admin origin.",
      next,
    };
  }

  const adminClient = getAdminSupabaseClient();
  const requestLimit = await enforceRateLimit(
    adminClient,
    rateLimitConfig("auth_otp_request", email),
  );
  if (!requestLimit.allowed) {
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(adminClient, {
      eventType: "otp_rate_limited",
      email,
      ip,
      userAgent,
      result: "locked_out",
      metadata: { scope: "auth_otp_request" },
    });
    return {
      status: "error",
      message: formatLockoutMessage(requestLimit),
      email,
      next,
    };
  }

  // Supabase's /auth/v1/verify corrupts redirect_to when it contains query
  // params, so the magic-link fallback always lands on /dashboard. The OTP
  // path doesn't use this URL.
  const emailRedirectTo = new URL("/auth/callback", portalBaseUrl).toString();

  const supabase = await getServerSupabaseClient();
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo, shouldCreateUser: false },
  });

  if (error) {
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(adminClient, {
      eventType: "otp_request",
      email,
      ip,
      userAgent,
      result: error.message,
      metadata: { success: false },
    });
    console.error("[login] signInWithOtp failed", error);
    return {
      status: "error",
      message: "Could not send the sign-in code. Try again in a moment.",
      email,
      next,
    };
  }

  const { ip, userAgent } = await readClientHeaders();
  void logAuthEvent(adminClient, {
    eventType: "otp_request",
    email,
    ip,
    userAgent,
    result: "code_sent",
    metadata: { success: true },
  });
  return {
    status: "code_sent",
    message: `Code sent to ${email}. Enter the 6-digit code below.`,
    email,
    next,
    nextResendAt: Date.now() + RESEND_COOLDOWN_MS,
  };
}

export async function verifyOtpAction(
  _prev: LoginActionState,
  formData: FormData,
): Promise<LoginActionState> {
  const rawEmail = formData.get("email");
  const rawToken = formData.get("token");
  const next = safeNext(formData.get("next"));
  const validated = validateForAction(loginVerifyOtpSchema, {
    email: rawEmail,
    token: rawToken,
    next,
  });
  if (!validated.ok) {
    // Preserve the original UX split between bad email vs bad token by
    // re-running the email check on its own when the issue path is `email`.
    const emailIssue = validated.issues.find((i) => i.path === "email");
    if (emailIssue) {
      return { status: "error", message: "Missing or invalid email.", next };
    }
    const emailEcho =
      typeof rawEmail === "string" ? rawEmail.trim().toLowerCase() : "";
    return {
      status: "error",
      message: "Enter the 6-digit code from your email.",
      email: emailEcho,
      next,
    };
  }
  const email = validated.data.email;
  const token = validated.data.token;

  const adminClient = getAdminSupabaseClient();
  const verifyLimit = await enforceRateLimit(
    adminClient,
    rateLimitConfig("auth_otp_verify", email),
  );
  if (!verifyLimit.allowed) {
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(adminClient, {
      eventType: "otp_rate_limited",
      email,
      ip,
      userAgent,
      result: "locked_out",
    });
    return {
      status: "error",
      message: formatLockoutMessage(verifyLimit),
      email,
      next,
    };
  }

  const supabase = await getServerSupabaseClient();
  const { data: verifyData, error } = await supabase.auth.verifyOtp({
    email,
    token,
    type: "email",
  });

  if (error) {
    const remaining = verifyLimit.attemptsRemaining;
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(adminClient, {
      eventType: "otp_verify_fail",
      email,
      ip,
      userAgent,
      result: error.message,
      metadata: { attempts_remaining: remaining },
    });
    console.error("[login] verifyOtp failed", error.message);
    return {
      status: "error",
      message:
        remaining > 0
          ? `That code didn't match. ${remaining} attempt${remaining === 1 ? "" : "s"} left.`
          : "Too many wrong codes. Request a new one in 15 minutes.",
      email,
      next,
    };
  }

  await resetRateLimit(adminClient, "auth_otp_verify", email);
  const { ip, userAgent } = await readClientHeaders();
  void logAuthEvent(adminClient, {
    eventType: "otp_verify_success",
    userId: verifyData.user?.id ?? null,
    email,
    ip,
    userAgent,
    result: "ok",
  });
  // Supabase has set the auth cookies via the SSR client. Hand off to the
  // callback so it can resolve admin_users.status (invited -> verified ->
  // /onboarding, active -> /dashboard, deactivated -> /denied). B4 will
  // implement that logic; for now redirect straight to `next`.
  redirect(next);
}

export async function signOutAndRedirectAction() {
  const supabase = await getServerSupabaseClient();
  // Capture identity BEFORE signOut clears the cookies, so the audit
  // entry carries user_id + email_hash. Both are optional on the log
  // path so a failed getUser doesn't block signout.
  const { data: userData } = await supabase.auth.getUser();
  const { ip, userAgent } = await readClientHeaders();
  void logAuthEvent(getAdminSupabaseClient(), {
    eventType: "signout",
    userId: userData.user?.id ?? null,
    email: userData.user?.email ?? null,
    ip,
    userAgent,
    result: "ok",
  });
  await supabase.auth.signOut();
  redirect("/login");
}
