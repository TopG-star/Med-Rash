import { getSupabaseAdminClient, parseIdentityInput, resolveOrCreateUserId, resolveQuiz } from "./_shared/supabase";
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
import { requireParticipantAuth } from "./_shared/participant-auth";
import { validateOrRespond } from "./_shared/validate";
import { rankedEligibilitySchema } from "../../src/lib/schemas/leaderboard";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

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
    const validated = validateOrRespond(rankedEligibilitySchema, body);
    if (!validated.ok) return validated.response;
    const identity = parseIdentityInput(body);
    const quizRef = validated.data.quizId;

    const supabase = getSupabaseAdminClient();

    // A6 — per-device bucket (120/60s). Higher than profile_sync because the
    // Flutter app polls eligibility ahead of each ranked quiz start.
    const deviceLimit = await enforceRateLimit(
      supabase,
      rateLimitConfig("ranked_eligibility", identity.deviceInstallId),
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
    const quiz = await resolveQuiz(supabase, quizRef);

    const { data, error } = await supabase
      .from("attempts")
      .select("id")
      .eq("user_id", userId)
      .eq("quiz_id", quiz.id)
      .eq("mode", "ranked")
      .limit(1);

    if (error) {
      return jsonResponse(500, {
        ok: false,
        code: "ELIGIBILITY_QUERY_FAILED",
        message: error.message,
      });
    }

    const eligible = (data ?? []).length === 0;

    return jsonResponse(200, {
      ok: true,
      eligible,
      reason: eligible ? "ELIGIBLE" : "RANKED_ATTEMPT_ALREADY_EXISTS",
      quizSlug: quiz.slug,
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
