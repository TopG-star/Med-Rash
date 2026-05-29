import { getSupabaseAdminClient } from "./_shared/supabase";
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, requirePost, toV2Handler } from "./_shared/http";
import { requireParticipantAuth } from "./_shared/participant-auth";
import { extractRemoteIp } from "./_shared/turnstile";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

type QuestionRow = {
  id: string;
  prompt: string;
  options: string[];
  correct_index: number;
  explanation: string;
  position: number;
};

type QuizRow = {
  slug: string;
  title: string;
  category: string;
  product: string;
  summary: string;
  question_count_default: number;
  metadata: Record<string, unknown>;
  questions: QuestionRow[];
};

export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) return preflight;

  const methodError = requirePost(event);
  if (methodError) return methodError;

  const auth = requireParticipantAuth(event);
  if (!auth.ok) return auth.response;

  try {
    const supabase = getSupabaseAdminClient();

    // A6 — IP-keyed bucket (60/60s). Quiz catalog is participant-token gated
    // already; this stops a single misbehaving install from scraping the bank.
    const clientIp = extractRemoteIp(event.headers) ?? "unknown-ip";
    const ipLimit = await enforceRateLimit(
      supabase,
      rateLimitConfig("quiz_list", clientIp),
    );
    if (!ipLimit.allowed) {
      return jsonResponse(429, {
        ok: false,
        code: "RATE_LIMITED",
        message: formatLockoutMessage(ipLimit),
        retryAfterSeconds: ipLimit.retryAfterSeconds,
      });
    }

    const { data, error } = await supabase
      .from("quizzes")
      .select(
        "slug, title, category, product, summary, question_count_default, metadata, questions(id, prompt, options, correct_index, explanation, position)",
      )
      .eq("is_active", true)
      .order("position", { referencedTable: "questions", ascending: true });

    if (error) {
      return jsonResponse(500, {
        ok: false,
        code: "QUIZ_FETCH_FAILED",
        message: error.message,
      });
    }

    const quizzes = (data as QuizRow[] | null) ?? [];

    return jsonResponse(200, { ok: true, quizzes });
  } catch (err) {
    return jsonResponse(500, {
      ok: false,
      code: "UNEXPECTED_ERROR",
      message: err instanceof Error ? err.message : "Unexpected error.",
    });
  }
}

export default toV2Handler(handler);
