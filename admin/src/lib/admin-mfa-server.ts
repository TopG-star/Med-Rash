import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";
import { getServerSupabaseClient } from "./supabase-ssr";
import { hashRecoveryCode, matchRecoveryCode } from "./admin-mfa";

// Slice B1 P2 — MFA I/O surface.
//
// Wraps the service-role client for storing/consuming recovery code hashes
// and exposes a small "status" reader for the AAL2 guard. Server-only.

export type MfaStatus = {
  /** True iff the user has at least one TOTP factor in `verified` state. */
  hasVerifiedFactor: boolean;
  /** Current Supabase Authenticator Assurance Level for the session. */
  currentLevel: "aal1" | "aal2" | null;
  /** Highest AAL the user has ever reached (i.e. did they enroll?). */
  nextLevel: "aal1" | "aal2" | null;
  /**
   * Factor IDs in `unverified` state — produced by an interrupted enroll.
   * We surface them so the page can offer "resume enrollment" and clean
   * them up rather than leak factor rows.
   */
  unverifiedFactorIds: string[];
};

/**
 * Read MFA status for the currently signed-in user via the cookie-bound
 * Supabase client. Returns null when there is no user (caller should
 * have already redirected to /login at that point — defence-in-depth).
 */
export async function readMfaStatus(): Promise<MfaStatus | null> {
  const supabase = await getServerSupabaseClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return null;

  const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  const { data: factorsData } = await supabase.auth.mfa.listFactors();

  const totpVerified = factorsData?.totp ?? [];
  const hasVerifiedFactor = totpVerified.length > 0;
  // Per supabase-js typing, `factorsData.totp` only contains `verified`
  // factors; orphaned `unverified` factors live in `factorsData.all`.
  const unverifiedFactorIds = (factorsData?.all ?? [])
    .filter((f) => f.factor_type === "totp" && f.status === "unverified")
    .map((f) => f.id);

  return {
    hasVerifiedFactor,
    currentLevel: (aalData?.currentLevel as MfaStatus["currentLevel"]) ?? null,
    nextLevel: (aalData?.nextLevel as MfaStatus["nextLevel"]) ?? null,
    unverifiedFactorIds,
  };
}

/**
 * Persist freshly-generated recovery code hashes alongside the enrollment
 * timestamp. Overwrites any previous recovery code set (intentional — the
 * old ones are invalidated as soon as a new enrollment completes).
 */
export async function persistEnrollment(
  userId: string,
  recoveryCodes: string[],
): Promise<{ ok: true } | { ok: false; error: string }> {
  const admin = getAdminSupabaseClient();
  const hashes = recoveryCodes.map(hashRecoveryCode);
  const { error } = await admin
    .from("admin_users")
    .update({
      mfa_recovery_codes_hashed: hashes,
      mfa_enrolled_at: new Date().toISOString(),
    })
    .eq("user_id", userId);
  if (error) {
    console.error("[admin-mfa] persistEnrollment failed", error);
    return { ok: false, error: error.message };
  }
  return { ok: true };
}

/**
 * Single-use recovery code consumption. Reads stored hashes, finds a
 * constant-time match, writes back the array minus the consumed entry.
 * Returns `{ ok: true, remaining: N }` on success, `{ ok: false, ... }`
 * on miss or DB failure.
 *
 * The plaintext `code` MUST come from the user via a Server Action — never
 * accept it from a client-side caller.
 */
export async function consumeRecoveryCode(
  userId: string,
  code: string,
): Promise<
  | { ok: true; remaining: number }
  | { ok: false; reason: "no_match" | "db_error"; message?: string }
> {
  const admin = getAdminSupabaseClient();
  const { data, error } = await admin
    .from("admin_users")
    .select("mfa_recovery_codes_hashed")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    console.error("[admin-mfa] consumeRecoveryCode read failed", error);
    return { ok: false, reason: "db_error", message: error.message };
  }
  const hashes: string[] = Array.isArray(data?.mfa_recovery_codes_hashed)
    ? (data!.mfa_recovery_codes_hashed as string[])
    : [];
  const matched = matchRecoveryCode(code, hashes);
  if (!matched) return { ok: false, reason: "no_match" };

  const remaining = hashes.filter((h) => h !== matched);
  const { error: updateError } = await admin
    .from("admin_users")
    .update({ mfa_recovery_codes_hashed: remaining })
    .eq("user_id", userId);
  if (updateError) {
    console.error("[admin-mfa] consumeRecoveryCode update failed", updateError);
    return { ok: false, reason: "db_error", message: updateError.message };
  }
  return { ok: true, remaining: remaining.length };
}

/**
 * Delete every TOTP factor on the user's account via service-role admin
 * API. Used by the recovery flow ("lost device") and the explicit "disable
 * MFA" action (which itself is gated on a fresh AAL2 step-up).
 *
 * Returns the number of factors deleted.
 */
export async function deleteAllTotpFactors(
  userId: string,
): Promise<{ ok: true; deleted: number } | { ok: false; error: string }> {
  const admin = getAdminSupabaseClient();
  const { data, error } = await admin.auth.admin.mfa.listFactors({ userId });
  if (error) {
    console.error("[admin-mfa] listFactors failed", error);
    return { ok: false, error: error.message };
  }
  const totp = (data?.factors ?? []).filter((f) => f.factor_type === "totp");
  let deleted = 0;
  for (const factor of totp) {
    const { error: delError } = await admin.auth.admin.mfa.deleteFactor({
      userId,
      id: factor.id,
    });
    if (delError) {
      console.error("[admin-mfa] deleteFactor failed", delError);
      return { ok: false, error: delError.message };
    }
    deleted += 1;
  }
  return { ok: true, deleted };
}
