"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/admin-session";
import {
  consumeRecoveryCode,
  deleteAllTotpFactors,
  persistEnrollment,
  readMfaStatus,
} from "@/lib/admin-mfa-server";
import { generateRecoveryCodes } from "@/lib/admin-mfa";
import { logAuthEvent } from "@/lib/audit";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
  resetRateLimit,
} from "@/lib/rate-limit";
import { getAdminSupabaseClient } from "@/lib/supabase-server";
import { getServerSupabaseClient } from "@/lib/supabase-ssr";

import {
  initialMfaChallengeState,
  initialMfaEnrollState,
  initialMfaRecoveryState,
  safeNext,
  type MfaChallengeState,
  type MfaEnrollState,
  type MfaRecoveryState,
} from "./state";

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

/**
 * Step 1 of enrollment — request a new TOTP factor from Supabase and
 * return the QR code data URL + alphanumeric secret. Both must be
 * displayed exactly once; we never persist the secret server-side
 * (Supabase already does, scoped to the user).
 */
export async function startEnrollmentAction(
  _prev: MfaEnrollState,
  _formData: FormData,
): Promise<MfaEnrollState> {
  const session = await requireAdminSession({ currentPath: "/onboarding/mfa" });
  if (session.role !== "owner") {
    redirect("/dashboard");
  }

  const supabase = await getServerSupabaseClient();

  // Clean up any orphaned unverified factor from an interrupted prior
  // attempt; if we don't, Supabase rejects a second enroll() with
  // "user already has a factor of this type".
  const status = await readMfaStatus();
  if (status && status.unverifiedFactorIds.length > 0) {
    for (const id of status.unverifiedFactorIds) {
      await supabase.auth.mfa.unenroll({ factorId: id });
    }
  }

  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: `MedRash Admin (${session.email})`,
  });
  if (error || !data) {
    console.error("[mfa] enroll failed", error);
    return {
      status: "error",
      message: "Could not start MFA enrollment. Try again in a moment.",
    };
  }
  return {
    status: "enrolling",
    factorId: data.id,
    qrSvg: data.totp.qr_code,
    secret: data.totp.secret,
  };
}

/**
 * Step 2 of enrollment — user types the 6-digit code from their
 * authenticator app, we challenge + verify it, generate 8 recovery codes
 * (shown once), persist their hashes, and emit the `mfa_enroll` audit
 * event.
 */
export async function verifyEnrollmentAction(
  _prev: MfaEnrollState,
  formData: FormData,
): Promise<MfaEnrollState> {
  const session = await requireAdminSession({ currentPath: "/onboarding/mfa" });
  if (session.role !== "owner") {
    redirect("/dashboard");
  }

  const factorId = formData.get("factor_id");
  const code = formData.get("code");
  const next = safeNext(formData.get("next"));
  if (typeof factorId !== "string" || typeof code !== "string" || !code.trim()) {
    return { status: "error", message: "Missing factor id or code." };
  }

  const supabase = await getServerSupabaseClient();
  const { data: challengeData, error: challengeError } =
    await supabase.auth.mfa.challenge({ factorId });
  if (challengeError || !challengeData) {
    console.error("[mfa] challenge failed", challengeError);
    return {
      status: "error",
      message: "Could not verify the code. Try again.",
    };
  }
  const { error: verifyError } = await supabase.auth.mfa.verify({
    factorId,
    challengeId: challengeData.id,
    code: code.trim(),
  });
  const { ip, userAgent } = await readClientHeaders();
  const adminClient = getAdminSupabaseClient();
  if (verifyError) {
    void logAuthEvent(adminClient, {
      eventType: "mfa_verify_fail",
      userId: session.userId,
      email: session.email,
      ip,
      userAgent,
      result: verifyError.message,
      metadata: { phase: "enroll", factor_id: factorId },
    });
    return { status: "error", message: "That code didn't match. Try again." };
  }

  const recoveryCodes = generateRecoveryCodes();
  const persisted = await persistEnrollment(session.userId, recoveryCodes);
  if (!persisted.ok) {
    return {
      status: "error",
      message:
        "Could not save recovery codes — your factor is verified but you may need to re-enroll. Contact another owner.",
    };
  }
  void logAuthEvent(adminClient, {
    eventType: "mfa_enroll",
    userId: session.userId,
    email: session.email,
    ip,
    userAgent,
    result: "ok",
    metadata: { factor_id: factorId, recovery_codes_issued: recoveryCodes.length },
  });
  // The verify call already promoted the session to AAL2 — no extra step.
  return { status: "enrolled", recoveryCodes, nextPath: next };
}

/**
 * Step-up challenge for a returning owner who has an enrolled factor but
 * the current session is AAL1. Reads the (single) verified factor id
 * server-side so the client never has to know it.
 */
export async function challengeAction(
  _prev: MfaChallengeState,
  formData: FormData,
): Promise<MfaChallengeState> {
  const session = await requireAdminSession({ currentPath: "/onboarding/mfa" });
  if (session.role !== "owner") {
    redirect("/dashboard");
  }

  const code = formData.get("code");
  const next = safeNext(formData.get("next"));
  if (typeof code !== "string" || !code.trim()) {
    return { status: "error", message: "Enter the 6-digit code." };
  }

  const adminClient = getAdminSupabaseClient();
  const limit = await enforceRateLimit(
    adminClient,
    rateLimitConfig("auth_mfa_verify", session.userId),
  );
  if (!limit.allowed) {
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(adminClient, {
      eventType: "mfa_verify_fail",
      userId: session.userId,
      email: session.email,
      ip,
      userAgent,
      result: "rate_limited",
      metadata: { scope: "auth_mfa_verify" },
    });
    return { status: "error", message: formatLockoutMessage(limit) };
  }

  const supabase = await getServerSupabaseClient();
  const { data: factorsData } = await supabase.auth.mfa.listFactors();
  const verifiedFactor = (factorsData?.totp ?? []).find(
    (f) => f.status === "verified",
  );
  if (!verifiedFactor) {
    // Edge case: AAL1 owner with no factor reached this action somehow —
    // shouldn't happen because page branches on hasVerifiedFactor, but
    // guard anyway.
    redirect(`/onboarding/mfa?next=${encodeURIComponent(next)}`);
  }
  const { data: challengeData, error: challengeError } =
    await supabase.auth.mfa.challenge({ factorId: verifiedFactor.id });
  if (challengeError || !challengeData) {
    console.error("[mfa] challenge failed", challengeError);
    return { status: "error", message: "Could not verify. Try again." };
  }
  const { error: verifyError } = await supabase.auth.mfa.verify({
    factorId: verifiedFactor.id,
    challengeId: challengeData.id,
    code: code.trim(),
  });
  const { ip, userAgent } = await readClientHeaders();
  if (verifyError) {
    void logAuthEvent(adminClient, {
      eventType: "mfa_verify_fail",
      userId: session.userId,
      email: session.email,
      ip,
      userAgent,
      result: verifyError.message,
      metadata: { phase: "challenge", attempts_remaining: limit.attemptsRemaining - 1 },
    });
    const remaining = limit.attemptsRemaining - 1;
    return {
      status: "error",
      message:
        remaining > 0
          ? `That code didn't match. ${remaining} attempt${remaining === 1 ? "" : "s"} left.`
          : "Too many wrong codes. Try again in 15 minutes.",
      attemptsRemaining: remaining,
    };
  }
  await resetRateLimit(adminClient, "auth_mfa_verify", session.userId);
  void logAuthEvent(adminClient, {
    eventType: "mfa_verify_success",
    userId: session.userId,
    email: session.email,
    ip,
    userAgent,
    result: "ok",
    metadata: { phase: "challenge" },
  });
  redirect(next);
}

/**
 * Recovery flow — user lost their authenticator. They submit one of the
 * 8 single-use codes from enrollment; on match we delete every TOTP
 * factor so they fall back to AAL1, then redirect them through enrollment
 * again. Audit-logged as `mfa_recovery_used`.
 */
export async function useRecoveryAction(
  _prev: MfaRecoveryState,
  formData: FormData,
): Promise<MfaRecoveryState> {
  const session = await requireAdminSession({ currentPath: "/onboarding/mfa" });
  if (session.role !== "owner") {
    redirect("/dashboard");
  }

  const code = formData.get("recovery_code");
  if (typeof code !== "string" || !code.trim()) {
    return { status: "error", message: "Enter a recovery code." };
  }

  const adminClient = getAdminSupabaseClient();
  const limit = await enforceRateLimit(
    adminClient,
    rateLimitConfig("auth_mfa_recovery", session.userId),
  );
  if (!limit.allowed) {
    const { ip, userAgent } = await readClientHeaders();
    void logAuthEvent(adminClient, {
      eventType: "mfa_recovery_used",
      userId: session.userId,
      email: session.email,
      ip,
      userAgent,
      result: "rate_limited",
    });
    return { status: "error", message: formatLockoutMessage(limit) };
  }

  const consumed = await consumeRecoveryCode(session.userId, code.trim());
  const { ip, userAgent } = await readClientHeaders();
  if (!consumed.ok) {
    if (consumed.reason === "no_match") {
      void logAuthEvent(adminClient, {
        eventType: "mfa_recovery_used",
        userId: session.userId,
        email: session.email,
        ip,
        userAgent,
        result: "no_match",
      });
      return { status: "error", message: "That recovery code is not valid." };
    }
    return { status: "error", message: "Could not consume the code. Try again." };
  }

  // Wipe every TOTP factor — user must re-enroll on a new device. This
  // also drops the session to AAL1 on the next request, which is exactly
  // what we want so they re-prove possession of a fresh authenticator.
  const remaining = consumed.remaining;
  const deleted = await deleteAllTotpFactors(session.userId);
  void logAuthEvent(adminClient, {
    eventType: "mfa_recovery_used",
    userId: session.userId,
    email: session.email,
    ip,
    userAgent,
    result: "ok",
    metadata: {
      recovery_codes_remaining: remaining,
      factors_deleted: deleted.ok ? deleted.deleted : 0,
    },
  });
  // Reload the page so it re-reads MfaStatus and shows enroll UI.
  redirect("/onboarding/mfa");
}

/**
 * Owner-initiated explicit disable. Gated on the current session already
 * being AAL2 (the user just challenged successfully). Emits the
 * `mfa_disable` audit event.
 *
 * Wired into the dashboard's account settings — for now the helper exists
 * but the UI surface lives in a follow-up slice.
 */
export async function disableMfaAction(): Promise<{ ok: true } | { ok: false; message: string }> {
  const session = await requireAdminSession({ currentPath: "/onboarding/mfa" });
  if (session.role !== "owner") {
    return { ok: false, message: "Not authorised." };
  }
  const supabase = await getServerSupabaseClient();
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.currentLevel !== "aal2") {
    return { ok: false, message: "Re-verify your MFA code before disabling." };
  }
  const result = await deleteAllTotpFactors(session.userId);
  const { ip, userAgent } = await readClientHeaders();
  void logAuthEvent(getAdminSupabaseClient(), {
    eventType: "mfa_disable",
    userId: session.userId,
    email: session.email,
    ip,
    userAgent,
    result: result.ok ? "ok" : "error",
    metadata: { factors_deleted: result.ok ? result.deleted : 0 },
  });
  if (!result.ok) return { ok: false, message: result.error };
  return { ok: true };
}
