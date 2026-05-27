"use server";

import { redirect } from "next/navigation";

import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
  resetRateLimit,
} from "@/lib/rate-limit";
import { getAdminSupabaseClient } from "@/lib/supabase-server";
import { getServerSupabaseClient } from "@/lib/supabase-ssr";
import type { LoginActionState } from "./state";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const OTP_RE = /^\d{6}$/;
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
  const email =
    typeof formData.get("email") === "string"
      ? (formData.get("email") as string).trim().toLowerCase()
      : "";
  const next = safeNext(formData.get("next"));

  if (!EMAIL_RE.test(email)) {
    return { status: "error", message: "Enter a valid work email.", next };
  }

  const portalBaseUrl = getPortalBaseUrl();
  if (!portalBaseUrl) {
    return {
      status: "error",
      message:
        "Server is missing MEDRASH_ADMIN_PORTAL_BASE_URL — set it to the deployed admin origin.",
      next,
    };
  }

  const requestLimit = await enforceRateLimit(
    getAdminSupabaseClient(),
    rateLimitConfig("auth_otp_request", email),
  );
  if (!requestLimit.allowed) {
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
    console.error("[login] signInWithOtp failed", error);
    return {
      status: "error",
      message: "Could not send the sign-in code. Try again in a moment.",
      email,
      next,
    };
  }

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
  const email =
    typeof formData.get("email") === "string"
      ? (formData.get("email") as string).trim().toLowerCase()
      : "";
  const token =
    typeof formData.get("token") === "string"
      ? (formData.get("token") as string).replace(/\s+/g, "")
      : "";
  const next = safeNext(formData.get("next"));

  if (!EMAIL_RE.test(email)) {
    return { status: "error", message: "Missing or invalid email.", next };
  }
  if (!OTP_RE.test(token)) {
    return {
      status: "error",
      message: "Enter the 6-digit code from your email.",
      email,
      next,
    };
  }

  const adminClient = getAdminSupabaseClient();
  const verifyLimit = await enforceRateLimit(
    adminClient,
    rateLimitConfig("auth_otp_verify", email),
  );
  if (!verifyLimit.allowed) {
    return {
      status: "error",
      message: formatLockoutMessage(verifyLimit),
      email,
      next,
    };
  }

  const supabase = await getServerSupabaseClient();
  const { error } = await supabase.auth.verifyOtp({
    email,
    token,
    type: "email",
  });

  if (error) {
    const remaining = verifyLimit.attemptsRemaining;
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
  // Supabase has set the auth cookies via the SSR client. Hand off to the
  // callback so it can resolve admin_users.status (invited -> verified ->
  // /onboarding, active -> /dashboard, deactivated -> /denied). B4 will
  // implement that logic; for now redirect straight to `next`.
  redirect(next);
}

export async function signOutAndRedirectAction() {
  const supabase = await getServerSupabaseClient();
  await supabase.auth.signOut();
  redirect("/login");
}
