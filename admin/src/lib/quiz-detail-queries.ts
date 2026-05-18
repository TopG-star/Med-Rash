import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";
import type { QuestionRecord, QuizRecord } from "./quiz-bank-types";

export type AdminQuizDetail = {
  quiz: QuizRecord;
  questions: QuestionRecord[];
};

type QuizRowDb = {
  id: string;
  slug: string;
  title: string;
  category: string | null;
  product: string | null;
  summary: string | null;
  question_count_default: number | null;
  is_active: boolean | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
};

type QuestionRowDb = {
  id: string;
  quiz_id: string;
  prompt: string;
  options: unknown;
  correct_index: number;
  explanation: string;
  clinical_area: string | null;
  tags: string[] | null;
  position: number | null;
  is_active: boolean | null;
  created_at: string;
};

function toQuiz(row: QuizRowDb): QuizRecord {
  return {
    id: row.id,
    slug: row.slug,
    title: row.title,
    category: row.category ?? "",
    product: row.product,
    summary: row.summary ?? "",
    questionCountDefault: row.question_count_default ?? 0,
    isActive: row.is_active ?? false,
    metadata: row.metadata ?? {},
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toQuestion(row: QuestionRowDb): QuestionRecord {
  const options = Array.isArray(row.options)
    ? (row.options as unknown[]).map((o) => String(o))
    : [];
  return {
    id: row.id,
    quizId: row.quiz_id,
    prompt: row.prompt,
    options,
    correctIndex: row.correct_index,
    explanation: row.explanation,
    clinicalArea: row.clinical_area,
    tags: row.tags ?? [],
    position: row.position ?? 0,
    isActive: row.is_active ?? false,
    createdAt: row.created_at,
  };
}

/**
 * Load a single quiz by slug with ALL its questions (active + inactive)
 * ordered by position for the admin detail page.
 */
export async function getAdminQuizDetailBySlug(
  slug: string,
): Promise<AdminQuizDetail | null> {
  const supabase = getAdminSupabaseClient();

  const { data: quizRow, error: quizErr } = await supabase
    .from("quizzes")
    .select(
      "id, slug, title, category, product, summary, question_count_default, is_active, metadata, created_at, updated_at",
    )
    .eq("slug", slug)
    .maybeSingle();

  if (quizErr) {
    throw new Error(`Failed to load quiz '${slug}': ${quizErr.message}`);
  }
  if (!quizRow) return null;

  const quiz = toQuiz(quizRow as QuizRowDb);

  const { data: qRows, error: qErr } = await supabase
    .from("questions")
    .select(
      "id, quiz_id, prompt, options, correct_index, explanation, clinical_area, tags, position, is_active, created_at",
    )
    .eq("quiz_id", quiz.id)
    .order("position", { ascending: true })
    .order("created_at", { ascending: true });

  if (qErr) {
    throw new Error(`Failed to load questions for '${slug}': ${qErr.message}`);
  }

  const questions = ((qRows as QuestionRowDb[] | null) ?? []).map(toQuestion);
  return { quiz, questions };
}
