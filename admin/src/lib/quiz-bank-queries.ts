import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type AdminQuizSummary = {
  id: string;
  slug: string;
  title: string;
  category: string;
  product: string;
  summary: string;
  questionCount: number;
  questionCountDefault: number;
  isActive: boolean;
  updatedAt: string;
  sampleQuestions: string[];
};

type QuizRow = {
  id: string;
  slug: string;
  title: string;
  category: string | null;
  product: string | null;
  summary: string | null;
  question_count_default: number | null;
  is_active: boolean | null;
  updated_at: string | null;
  questions:
    | Array<{ id: string; prompt: string | null; position: number | null }>
    | null;
};

/**
 * List quizzes for the Quiz Bank admin surface, including a count of attached
 * questions and the first two prompts as a preview.
 *
 * Reads directly from Supabase using the service-role client (server-only).
 */
export async function listAdminQuizzes(): Promise<AdminQuizSummary[]> {
  const supabase = getAdminSupabaseClient();

  const { data, error } = await supabase
    .from("quizzes")
    .select(
      "id, slug, title, category, product, summary, question_count_default, is_active, updated_at, questions(id, prompt, position)",
    )
    .order("updated_at", { ascending: false });

  if (error) {
    throw new Error(`Failed to load admin quizzes: ${error.message}`);
  }

  const rows = (data as QuizRow[] | null) ?? [];

  return rows.map((row) => {
    const questions = (row.questions ?? [])
      .slice()
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));

    return {
      id: row.id,
      slug: row.slug,
      title: row.title,
      category: row.category ?? "",
      product: row.product ?? "",
      summary: row.summary ?? "",
      questionCount: questions.length,
      questionCountDefault: row.question_count_default ?? 0,
      isActive: row.is_active ?? false,
      updatedAt: row.updated_at ?? "",
      sampleQuestions: questions
        .slice(0, 2)
        .map((q) => (q.prompt ?? "").trim())
        .filter((p) => p.length > 0),
    };
  });
}
