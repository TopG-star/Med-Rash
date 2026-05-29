import {
  findUserByRecoveryEmail,
  getSupabaseAdminClient,
  getSupabaseAuthClient,
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
import { requireParticipantAuth } from "./_shared/participant-auth";
import { validateOrRespond } from "./_shared/validate";
import { extractRemoteIp } from "./_shared/turnstile";
import { logAuthEvent } from "../../src/lib/audit";
import { recoverRequestSchema } from "../../src/lib/schemas/recover";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

// Slice 6b — step 1 of OTP-confirmed identity recovery.
//
// Flow:
//   1. Client posts { email } from the /recover entry page.
//   2. Look up app.users by lower(email). If no row carries that email,
//      return 404 PROFILE_NOT_FOUND so the UI can say "no profile found".
//   3. Ask Supabase Auth to send a one-time code to that email via the
//      anon-keyed auth client (signInWithOtp). shouldCreateUser is true so
//      the auth.users row is provisioned lazily on first recover; that row
//      is what we'll write into app.users.claimed_auth_user_id on step 2.
//
// Rate limiting is delegated to Supabase Auth (per-email + per-project).
// Verification lives in recover-verify.ts.
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
    const validated = validateOrRespond(recoverRequestSchema, body);
    if (!validated.ok) return validated.response;
    const { email } = validated.data;

    const supabase = getSupabaseAdminClient();
    const ip = extractRemoteIp(event.headers);
    const userAgent = event.headers?.["user-agent"] ?? null;

    const limit = await enforceRateLimit(
      supabase,
      rateLimitConfig("recover_otp_request", email),
    );
    if (!limit.allowed) {
      void logAuthEvent(supabase, {
        eventType: "recover_rate_limited",
        email,
        ip,
        userAgent,
        result: "locked_out",
        metadata: { scope: "recover_otp_request" },
      });
      return jsonResponse(429, {
        ok: false,
        code: "RATE_LIMITED",
        message: formatLockoutMessage(limit),
        retryAfterSeconds: limit.retryAfterSeconds,
      });
    }

    const existing = await findUserByRecoveryEmail(supabase, email);

    if (!existing) {
      void logAuthEvent(supabase, {
        eventType: "recover_request",
        email,
        ip,
        userAgent,
        result: "profile_not_found",
      });
      return jsonResponse(404, {
        ok: false,
        code: "PROFILE_NOT_FOUND",
        message: "No profile is linked to that email. Check the spelling or start a new profile.",
      });
    }

    const auth = getSupabaseAuthClient();
    const { error } = await auth.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: true,
      },
    });

    if (error) {
      const status = typeof (error as { status?: number }).status === "number" ? (error as { status: number }).status : 0;
      if (status === 429) {
        void logAuthEvent(supabase, {
          eventType: "recover_rate_limited",
          email,
          ip,
          userAgent,
          result: "supabase_429",
        });
        return jsonResponse(429, {
          ok: false,
          code: "RATE_LIMITED",
          message: "Too many recovery codes requested. Wait a minute and try again.",
        });
      }
      void logAuthEvent(supabase, {
        eventType: "recover_request",
        email,
        ip,
        userAgent,
        result: "otp_send_failed",
        metadata: { supabase_status: status, error: error.message },
      });
      return jsonResponse(502, {
        ok: false,
        code: "OTP_SEND_FAILED",
        message: "Couldn't send the recovery code. Try again in a moment.",
      });
    }

    void logAuthEvent(supabase, {
      eventType: "recover_request",
      email,
      ip,
      userAgent,
      result: "code_sent",
    });
    return jsonResponse(200, {
      ok: true,
      message: "Recovery code sent. Check your email.",
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
