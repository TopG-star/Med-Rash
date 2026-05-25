import { PostgrestError } from "@supabase/supabase-js";

import { EmailTakenError, getSupabaseAdminClient, isUniqueViolation, parseIdentityInput, resolveOrCreateUserId, resolveQuiz } from "./_shared/supabase";
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
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

    // Clamp time to a sane upper bound (2 hours) to defend against clock skew
    // or a stuck attempt sending an obscene duration.
    const MAX_TIME_TAKEN_MS = 2 * 60 * 60 * 1000;
    const clampedTimeTakenMs = Math.min(timeTakenMs, MAX_TIME_TAKEN_MS);

    const now = new Date();

    const supabase = getSupabaseAdminClient();
    const userId = await resolveOrCreateUserId(supabase, identity);
    const quiz = await resolveQuiz(supabase, quizRef);

    // Server-side score recomputation. We never trust client-supplied score
    // or is_correct flags — fetch the truth table for this quiz and rebuild
    // the verdict locally.
    const { data: questionsRows, error: questionsError } = await supabase
      .from("questions")
      .select("id, correct_index")
      .eq("quiz_id", quiz.id);

    if (questionsError) {
      return jsonResponse(500, {
        ok: false,
        code: "QUIZ_QUESTIONS_FETCH_FAILED",
        message: questionsError.message,
      });
    }

    const correctIndexByQuestionId = new Map<string, number>();
    for (const row of (questionsRows ?? []) as Array<Record<string, unknown>>) {
      const id = typeof row.id === "string" ? row.id : null;
      const correctIndex =
        typeof row.correct_index === "number" ? Math.floor(row.correct_index) : null;
      if (id && correctIndex !== null) {
        correctIndexByQuestionId.set(id, correctIndex);
      }
    }

    const submittedAnswers = parseAnswers(body);

    // Filter answers down to ones whose questionId belongs to this quiz, then
    // recompute is_correct from the server's correct_index. Anything else is
    // dropped (and logged) so analytics stays trustworthy.
    type RecomputedAnswer = AnswerInput & { recomputedIsCorrect: boolean };
    const recomputedAnswers: RecomputedAnswer[] = [];
    let droppedAnswerCount = 0;
    for (const a of submittedAnswers) {
      const correctIndex = correctIndexByQuestionId.get(a.questionId);
      if (correctIndex === undefined) {
        droppedAnswerCount += 1;
        continue;
      }
      recomputedAnswers.push({
        ...a,
        recomputedIsCorrect: a.selectedIndex === correctIndex,
      });
    }

    if (droppedAnswerCount > 0) {
      console.warn(
        `[attempt-submit] dropped ${droppedAnswerCount} answer(s) whose questionId did not belong to quiz ${quiz.id}.`,
      );
    }

    // Server-of-record values. We ignore the client-supplied score and
    // totalQuestions entirely; totalQuestions is the size of the quiz's
    // question bank (or the client-provided value, whichever is smaller and
    // positive — to defend against partial seeds during local dev).
    const recomputedScore = recomputedAnswers.reduce(
      (sum, a) => sum + (a.recomputedIsCorrect ? 1 : 0),
      0,
    );
    const serverTotalQuestions =
      correctIndexByQuestionId.size > 0 ? correctIndexByQuestionId.size : totalQuestions;

    // Detect score tampering so we can alarm on it later without rejecting
    // the attempt — the server value is what gets persisted regardless.
    if (score !== recomputedScore || totalQuestions !== serverTotalQuestions) {
      console.warn(
        `[attempt-submit] client/server score mismatch for quiz ${quiz.id}: ` +
          `client=${score}/${totalQuestions} server=${recomputedScore}/${serverTotalQuestions}`,
      );
    }

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

    const startedAt = new Date(Math.max(now.getTime() - clampedTimeTakenMs, 0)).toISOString();
    const completedAt = now.toISOString();

    const { data: insertedAttempt, error: insertError } = await supabase
      .from("attempts")
      .insert({
        user_id: userId,
        quiz_id: quiz.id,
        session_id: sessionId,
        mode,
        origin,
        score: recomputedScore,
        total_questions: serverTotalQuestions,
        time_taken_ms: clampedTimeTakenMs,
        started_at: startedAt,
        completed_at: completedAt,
        metadata: {
          source: "netlify-gate",
          identity_spine_id: identity.participantId,
          quiz_slug: quiz.slug,
          client_reported_score: score,
          client_reported_total_questions: totalQuestions,
          dropped_answer_count: droppedAnswerCount,
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

    // Insert per-question answer records for analytics, using the server-
    // recomputed is_correct (not the client-supplied flag).
    // This is non-blocking: a failure here does not fail the attempt submission.
    if (recomputedAnswers.length > 0) {
      const answerRows = recomputedAnswers.map((a) => ({
        attempt_id: attemptId,
        question_id: a.questionId,
        selected_index: a.selectedIndex,
        selected_option_text: a.selectedOptionText,
        is_correct: a.recomputedIsCorrect,
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
      score: recomputedScore,
      totalQuestions: serverTotalQuestions,
      answersRecorded: recomputedAnswers.length > 0,
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
