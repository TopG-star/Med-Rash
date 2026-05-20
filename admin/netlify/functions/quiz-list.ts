import { getSupabaseAdminClient } from "./_shared/supabase";
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, requirePost } from "./_shared/http";
import { requireGateAuthorization } from "./_shared/gate";

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

  const gateError = requireGateAuthorization(event);
  if (gateError) return gateError;

  try {
    const supabase = getSupabaseAdminClient();

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
