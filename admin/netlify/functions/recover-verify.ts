import {
  bindDeviceToUser,
  findUserByRecoveryEmail,
  getSupabaseAdminClient,
  getSupabaseAuthClient,
  mergeUserInto,
  setClaimedAuthUserId,
} from "./_shared/supabase";
import {
  HandlerEvent,
  HandlerResponse,
  handlePreflight,
  jsonResponse,
  parseJsonBody,
  requirePost,
  toV2Handler,
} from "./_shared/http";
import { requireGateAuthorization } from "./_shared/gate";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
  resetRateLimit,
} from "../../src/lib/rate-limit";

// Slice 6b — step 2 of OTP-confirmed identity recovery.
//
// Flow:
//   1. Client posts { email, otp, deviceInstallId, currentParticipantId? }.
//      currentParticipantId is the freshly-minted guest user_id on this
//      device install; omitted only if the client truly has no spine yet.
//   2. Verify OTP via Supabase Auth -> get the authenticated auth.users.id.
//   3. Look up the recovered app.users row by lower(email). Bind its
//      claimed_auth_user_id (if not already set).
//   4. If a current guest user_id was supplied and differs from the
//      recovered id, run app.merge_user_into(source, target). The Postgres
//      function handles ranked dedup, learning re-point, device rotate,
//      session_join_events collisions, and source-row teardown atomically.
//   5. Bind this device install to the recovered user_id (rebind from
//      whichever device row points there now).
//   6. Return the full recovered identity payload so the client can swap
//      its AuthStateManager spine and persist the recovered profile.
export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) {
    return preflight;
  }

  const methodResponse = requirePost(event);
  if (methodResponse) {
    return methodResponse;
  }

  const gateResponse = requireGateAuthorization(event);
  if (gateResponse) {
    return gateResponse;
  }

  try {
    const body = parseJsonBody(event);
    const rawEmail = typeof body.email === "string" ? body.email : "";
    const email = rawEmail.trim().toLowerCase();
    const otp = typeof body.otp === "string" ? body.otp.trim() : "";
    const deviceInstallId = typeof body.deviceInstallId === "string" ? body.deviceInstallId.trim() : "";
    const currentParticipantId =
      typeof body.currentParticipantId === "string" ? body.currentParticipantId.trim() : "";

    if (!email || !otp || !deviceInstallId) {
      return jsonResponse(400, {
        ok: false,
        code: "BAD_REQUEST",
        message: "email, otp and deviceInstallId are required.",
      });
    }

    const supabase = getSupabaseAdminClient();

    const limit = await enforceRateLimit(
      supabase,
      rateLimitConfig("recover_otp_verify", email),
    );
    if (!limit.allowed) {
      return jsonResponse(429, {
        ok: false,
        code: "RATE_LIMITED",
        message: formatLockoutMessage(limit),
        retryAfterSeconds: limit.retryAfterSeconds,
      });
    }

    const auth = getSupabaseAuthClient();
    const { data: verified, error: verifyError } = await auth.auth.verifyOtp({
      email,
      token: otp,
      type: "email",
    });

    if (verifyError || !verified?.user?.id) {
      // Supabase returns a generic "Token has expired or is invalid" for both
      // cases. Surface a single OTP_INVALID code; the client can show one
      // friendly message and a "resend" affordance.
      return jsonResponse(400, {
        ok: false,
        code: "OTP_INVALID",
        message: "That code is invalid or expired. Request a new one and try again.",
      });
    }

    const authUserId = verified.user.id;
    const recovered = await findUserByRecoveryEmail(supabase, email);

    if (!recovered) {
      // The user verified the OTP but no app.users row matches. This only
      // happens if the recovery email was cleared between request and verify
      // (a race we don't otherwise expect). Treat as PROFILE_NOT_FOUND.
      return jsonResponse(404, {
        ok: false,
        code: "PROFILE_NOT_FOUND",
        message: "No profile is linked to that email any more. Start a new profile to keep playing.",
      });
    }

    // If the row is already claimed by a different auth user, refuse — this
    // would mean two Supabase Auth identities are racing for the same domain
    // profile. Practically impossible given UNIQUE(claimed_auth_user_id) +
    // single auth user per email, but worth being explicit.
    if (recovered.claimedAuthUserId && recovered.claimedAuthUserId !== authUserId) {
      return jsonResponse(409, {
        ok: false,
        code: "RECOVERY_CONFLICT",
        message: "This profile is already linked to a different account. Contact support.",
      });
    }

    if (!recovered.claimedAuthUserId) {
      await setClaimedAuthUserId(supabase, recovered.id, authUserId);
    }

    if (currentParticipantId && currentParticipantId !== recovered.id) {
      await mergeUserInto(supabase, currentParticipantId, recovered.id);
    }

    await bindDeviceToUser(supabase, recovered.id, deviceInstallId);

    await resetRateLimit(supabase, "recover_otp_verify", email);

    return jsonResponse(200, {
      ok: true,
      participantId: recovered.id,
      deviceInstallId,
      profile: {
        fullName: recovered.fullName,
        nickname: recovered.nickname,
        facility: recovered.facility,
        specialty: recovered.specialty,
        email: recovered.email,
      },
    });
  } catch (error) {
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: error instanceof Error ? error.message : "Invalid request.",
    });
  }
}

export default toV2Handler(handler);
