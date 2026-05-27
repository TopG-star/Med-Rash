import { getSupabaseAdminClient, parseIdentityInput, resolveOrCreateUserId, resolveQuiz } from "./_shared/supabase";
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
import { requireParticipantAuth } from "./_shared/participant-auth";

function readQuizRef(body: Record<string, unknown>): string {
  const value = body.quizId;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error("quizId is required.");
  }
  return value.trim();
}

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
    const quizRef = readQuizRef(body);

    const supabase = getSupabaseAdminClient();
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
