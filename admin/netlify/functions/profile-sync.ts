import { EmailTakenError, getSupabaseAdminClient, parseIdentityInput, resolveOrCreateUserId } from "./_shared/supabase";
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
import { requireParticipantAuth } from "./_shared/participant-auth";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

// Sync the device-bound profile (full name, nickname, facility, specialty) to
// the server-side `app.users` row without recording an attempt. Called by the
// Flutter app every time the user edits their profile so the leaderboard
// stops showing stale nicknames. Reuses `resolveOrCreateUserId`, which now
// always overwrites name fields on the existing-user branch.
export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) {
    return preflight;
  }

  const methodResponse = requirePost(event);
  if (methodResponse) {
    return methodResponse;
  }

  const auth = requireParticipantAuth(event);
  if (!auth.ok) {
    return auth.response;
  }

  try {
    const body = parseJsonBody(event);
    const identity = parseIdentityInput(body);

    const supabase = getSupabaseAdminClient();

    // A6 — per-device bucket (30/60s). Profile edits are interactive, so
    // 30/min is generous for a real user while killing scripted spam.
    const deviceLimit = await enforceRateLimit(
      supabase,
      rateLimitConfig("profile_sync", identity.deviceInstallId),
    );
    if (!deviceLimit.allowed) {
      return jsonResponse(429, {
        ok: false,
        code: "RATE_LIMITED",
        message: formatLockoutMessage(deviceLimit),
        retryAfterSeconds: deviceLimit.retryAfterSeconds,
      });
    }

    const userId = await resolveOrCreateUserId(supabase, identity);

    return jsonResponse(200, {
      ok: true,
      userId,
      profile: identity.profile,
    });
  } catch (error) {
    if (error instanceof EmailTakenError) {
      return jsonResponse(409, {
        ok: false,
        code: "EMAIL_TAKEN",
        message: "That email is already linked to another profile. Use a different email or leave it blank.",
      });
    }
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: error instanceof Error ? error.message : "Invalid request.",
    });
  }
}

export default toV2Handler(handler);
