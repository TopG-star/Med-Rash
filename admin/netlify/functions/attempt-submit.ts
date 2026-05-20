import { PostgrestError } from "@supabase/supabase-js";

import { getSupabaseAdminClient, isUniqueViolation, parseIdentityInput, resolveOrCreateUserId, resolveQuiz } from "./_shared/supabase";
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, parseJsonBody, requirePost } from "./_shared/http";
import { requireGateAuthorization } from "./_shared/gate";

type Mode = "learning" | "ranked";
type Origin = "qr_session" | "open_access";

function parseMode(value: unknown): Mode {
  if (value === "learning" || value === "ranked") {
    return value;
  }
  throw new Error("mode must be either learning or ranked.");
}

function parseOrigin(value: unknown): Origin {
  if (value === "qr_session" || value === "open_access") {
    return value;
  }
  return "open_access";
}

function parsePositiveInt(value: unknown, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }

  const rounded = Math.floor(value);
  if (rounded < 0) {
    return 0;
  }

  return rounded;
}

function parseQuizRef(body: Record<string, unknown>): string {
  const quizId = body.quizId;
  if (typeof quizId !== "string" || quizId.trim().length === 0) {
    throw new Error("quizId is required.");
  }

  return quizId.trim();
}

function parseSessionId(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

type AnswerInput = {
  questionId: string;
  selectedIndex: number;
  selectedOptionText: string;
  isCorrect: boolean;
  responseTimeMs: number;
};

function parseAnswers(body: Record<string, unknown>): AnswerInput[] {
  const raw = body.answers;
  if (!Array.isArray(raw)) return [];

  return raw
    .filter(
      (item): item is Record<string, unknown> =>
        item !== null && typeof item === "object" && !Array.isArray(item),
    )
    .filter(
      (item) =>
        typeof item.questionId === "string" &&
        (item.questionId as string).trim().length > 0 &&
        typeof item.selectedIndex === "number" &&
        (item.selectedIndex as number) >= 0,
    )
    .map((item) => ({
      questionId: (item.questionId as string).trim(),
      selectedIndex: Math.floor(item.selectedIndex as number),
      selectedOptionText:
        typeof item.selectedOptionText === "string" ? (item.selectedOptionText as string) : "",
      isCorrect: item.isCorrect === true,
      responseTimeMs:
        typeof item.responseTimeMs === "number"
          ? Math.max(0, Math.floor(item.responseTimeMs as number))
          : 0,
    }));
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

  const gateResponse = requireGateAuthorization(event);
  if (gateResponse) {
    return gateResponse;
  }

  try {
    const body = parseJsonBody(event);
    const identity = parseIdentityInput(body);
    const quizRef = parseQuizRef(body);
    const mode = parseMode(body.mode);
    const origin = parseOrigin(body.origin);
    const sessionId = parseSessionId(body.sessionId);

    if (origin === "qr_session" && !sessionId) {
      throw new Error("sessionId is required when origin is qr_session.");
    }

    const score = parsePositiveInt(body.score, 0);
    const totalQuestions = parsePositiveInt(body.totalQuestions, 5);
    const timeTakenMs = parsePositiveInt(body.timeTakenMs, 0);

    const now = new Date();

    const supabase = getSupabaseAdminClient();
    const userId = await resolveOrCreateUserId(supabase, identity);
    const quiz = await resolveQuiz(supabase, quizRef);

    if (mode === "ranked") {
      const { data: existingRanked, error: rankedCheckError } = await supabase
        .from("attempts")
        .select("id")
        .eq("user_id", userId)
        .eq("quiz_id", quiz.id)
        .eq("mode", "ranked")
        .limit(1);

      if (rankedCheckError) {
        return jsonResponse(500, {
          ok: false,
          code: "RANKED_ELIGIBILITY_CHECK_FAILED",
          message: rankedCheckError.message,
        });
      }

      if ((existingRanked ?? []).length > 0) {
        return jsonResponse(409, {
          ok: false,
          code: "RANKED_ATTEMPT_ALREADY_EXISTS",
          message: "Ranked attempt already exists for this user and quiz.",
        });
      }
    }

    const startedAt = new Date(Math.max(now.getTime() - timeTakenMs, 0)).toISOString();
    const completedAt = now.toISOString();

    const { data: insertedAttempt, error: insertError } = await supabase
      .from("attempts")
      .insert({
        user_id: userId,
        quiz_id: quiz.id,
        session_id: sessionId,
        mode,
        origin,
        score,
        total_questions: totalQuestions,
        time_taken_ms: timeTakenMs,
        started_at: startedAt,
        completed_at: completedAt,
        metadata: {
          source: "netlify-gate",
          identity_spine_id: identity.participantId,
          quiz_slug: quiz.slug,
        },
      })
      .select("id")
      .single();

    if (insertError) {
      if (mode === "ranked" && isUniqueViolation(insertError as PostgrestError)) {
        return jsonResponse(409, {
          ok: false,
          code: "RANKED_ATTEMPT_ALREADY_EXISTS",
          message: "Ranked attempt already exists for this user and quiz.",
        });
      }

      return jsonResponse(500, {
        ok: false,
        code: "ATTEMPT_INSERT_FAILED",
        message: insertError.message,
      });
    }

    const attemptId = String((insertedAttempt as Record<string, unknown>).id);

    // Insert per-question answer records for analytics.
    // This is non-blocking: a failure here does not fail the attempt submission.
    const answers = parseAnswers(body);
    if (answers.length > 0) {
      const answerRows = answers.map((a) => ({
        attempt_id: attemptId,
        question_id: a.questionId,
        selected_index: a.selectedIndex,
        selected_option_text: a.selectedOptionText,
        is_correct: a.isCorrect,
        response_time_ms: a.responseTimeMs,
      }));

      const { error: answersError } = await supabase.from("answers").insert(answerRows);
      if (answersError) {
        console.error("[attempt-submit] answers insert failed:", answersError.message);
      }
    }

    return jsonResponse(200, {
      ok: true,
      attemptId,
      quizSlug: quiz.slug,
      answersRecorded: answers.length > 0,
    });
  } catch (error) {
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: error instanceof Error ? error.message : "Invalid request.",
    });
  }
}

export default handler;
