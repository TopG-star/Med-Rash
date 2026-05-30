import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";
import {
  PILOT_QUESTION_OPTION_COUNT,
  type QuestionRecord,
  type QuizRecord,
} from "./quiz-bank-types";

export { PILOT_QUESTION_OPTION_COUNT };
export type { QuestionRecord, QuizRecord };

/* ============================================================================
 * Shared types
 * ========================================================================== */

export type CreateQuizInput = {
  slug: string;
  title: string;
  category: string;
  product: string | null;
  summary: string;
  questionCountDefault: number;
  isActive: boolean;
  metadata: Record<string, unknown>;
  createdBy: string | null;
};

export type UpdateQuizInput = {
  id: string;
  title: string;
  category: string;
  product: string | null;
  summary: string;
  questionCountDefault: number;
  isActive: boolean;
  metadata: Record<string, unknown>;
};

export type CreateQuestionInput = {
  quizId: string;
  prompt: string;
  options: string[]; // exactly 4 for pilot
  correctIndex: number; // 0..3
  explanation: string;
  clinicalArea: string | null;
  tags: string[];
  position: number | null; // null = append
  isActive: boolean;
  createdBy: string | null;
};

export type UpdateQuestionInput = {
  id: string;
  prompt: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  clinicalArea: string | null;
  tags: string[];
  position: number | null;
  isActive: boolean;
};

/* ============================================================================
 * Pilot constraints
 * ========================================================================== */
// Slug + length constants enforced upstream by `createQuizPayloadSchema` etc.

/* ============================================================================
 * DB row shapes (snake_case <-> camelCase)
 * ========================================================================== */

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

function mapQuiz(row: QuizRowDb): QuizRecord {
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

function mapQuestion(row: QuestionRowDb): QuestionRecord {
  const opts = Array.isArray(row.options)
    ? (row.options as unknown[]).map((o) => String(o))
    : [];
  return {
    id: row.id,
    quizId: row.quiz_id,
    prompt: row.prompt,
    options: opts,
    correctIndex: row.correct_index,
    explanation: row.explanation,
    clinicalArea: row.clinical_area,
    tags: row.tags ?? [],
    position: row.position ?? 0,
    isActive: row.is_active ?? false,
    createdAt: row.created_at,
  };
}

/* ============================================================================
 * Quiz mutations
 * ========================================================================== */

const QUIZ_COLUMNS =
  "id, slug, title, category, product, summary, question_count_default, is_active, metadata, created_at, updated_at";

export async function createQuizRecord(input: CreateQuizInput): Promise<QuizRecord> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("quizzes")
    .insert({
      slug: input.slug,
      title: input.title,
      category: input.category,
      // app.quizzes.product is NOT NULL DEFAULT '' (migration 003). Coerce
      // null to '' so admins can leave the field blank without tripping 23502.
      product: input.product ?? "",
      summary: input.summary,
      question_count_default: input.questionCountDefault,
      is_active: input.isActive,
      metadata: input.metadata,
      created_by: input.createdBy,
    })
    .select(QUIZ_COLUMNS)
    .single();

  if (error) {
    if ((error as { code?: string }).code === "23505") {
      throw new Error(`Quiz slug '${input.slug}' is already in use.`);
    }
    throw new Error(`Failed to create quiz: ${error.message}`);
  }
  return mapQuiz(data as QuizRowDb);
}

export async function updateQuizRecord(input: UpdateQuizInput): Promise<QuizRecord> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("quizzes")
    .update({
      title: input.title,
      category: input.category,
      product: input.product ?? "",
      summary: input.summary,
      question_count_default: input.questionCountDefault,
      is_active: input.isActive,
      metadata: input.metadata,
    })
    .eq("id", input.id)
    .select(QUIZ_COLUMNS)
    .single();

  if (error) {
    throw new Error(`Failed to update quiz: ${error.message}`);
  }
  if (!data) {
    throw new Error("Quiz not found.");
  }
  return mapQuiz(data as QuizRowDb);
}

/**
 * Soft-delete: flip is_active=false. Preserves historical attempts/answers.
 */
export async function deactivateQuizRecord(id: string): Promise<QuizRecord> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("quizzes")
    .update({ is_active: false })
    .eq("id", id)
    .select(QUIZ_COLUMNS)
    .single();

  if (error) {
    throw new Error(`Failed to deactivate quiz: ${error.message}`);
  }
  if (!data) {
    throw new Error("Quiz not found.");
  }
  return mapQuiz(data as QuizRowDb);
}

/* ============================================================================
 * Question mutations
 * ========================================================================== */

const QUESTION_COLUMNS =
  "id, quiz_id, prompt, options, correct_index, explanation, clinical_area, tags, position, is_active, created_at";

async function nextQuestionPosition(quizId: string): Promise<number> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("questions")
    .select("position")
    .eq("quiz_id", quizId)
    .order("position", { ascending: false })
    .limit(1);

  if (error) {
    throw new Error(`Failed to compute next question position: ${error.message}`);
  }
  const top = (data as Array<{ position: number | null }> | null)?.[0]?.position ?? -1;
  return top + 1;
}

export async function createQuestionRecord(
  input: CreateQuestionInput,
): Promise<QuestionRecord> {
  const supabase = getAdminSupabaseClient();

  const { data: quiz, error: quizErr } = await supabase
    .from("quizzes")
    .select("id")
    .eq("id", input.quizId)
    .maybeSingle();
  if (quizErr) {
    throw new Error(`Failed to verify quiz: ${quizErr.message}`);
  }
  if (!quiz) {
    throw new Error("Quiz not found for the supplied quizId.");
  }

  const position =
    input.position === null ? await nextQuestionPosition(input.quizId) : input.position;

  const { data, error } = await supabase
    .from("questions")
    .insert({
      quiz_id: input.quizId,
      prompt: input.prompt,
      options: input.options,
      correct_index: input.correctIndex,
      explanation: input.explanation,
      clinical_area: input.clinicalArea,
      tags: input.tags,
      position,
      is_active: input.isActive,
      created_by: input.createdBy,
    })
    .select(QUESTION_COLUMNS)
    .single();

  if (error) {
    throw new Error(`Failed to create question: ${error.message}`);
  }
  return mapQuestion(data as QuestionRowDb);
}

export async function updateQuestionRecord(
  input: UpdateQuestionInput,
): Promise<QuestionRecord> {
  const supabase = getAdminSupabaseClient();

  const updatePayload: Record<string, unknown> = {
    prompt: input.prompt,
    options: input.options,
    correct_index: input.correctIndex,
    explanation: input.explanation,
    clinical_area: input.clinicalArea,
    tags: input.tags,
    is_active: input.isActive,
  };
  if (input.position !== null) {
    updatePayload.position = input.position;
  }

  const { data, error } = await supabase
    .from("questions")
    .update(updatePayload)
    .eq("id", input.id)
    .select(QUESTION_COLUMNS)
    .single();

  if (error) {
    throw new Error(`Failed to update question: ${error.message}`);
  }
  if (!data) {
    throw new Error("Question not found.");
  }
  return mapQuestion(data as QuestionRowDb);
}

/**
 * Soft-delete: flip is_active=false. Preserves historical answer rows that
 * reference this question id.
 */
export async function deactivateQuestionRecord(id: string): Promise<QuestionRecord> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("questions")
    .update({ is_active: false })
    .eq("id", id)
    .select(QUESTION_COLUMNS)
    .single();

  if (error) {
    throw new Error(`Failed to deactivate question: ${error.message}`);
  }
  if (!data) {
    throw new Error("Question not found.");
  }
  return mapQuestion(data as QuestionRowDb);
}

/* ============================================================================
 * Bulk question import (CSV)
 * ========================================================================== */

export type BulkQuestionInput = Omit<
  CreateQuestionInput,
  "quizId" | "position" | "createdBy"
> & {
  position?: number | null;
};

export type BulkCreateQuestionsResult = {
  created: QuestionRecord[];
  failures: Array<{ index: number; message: string }>;
};

/**
 * Insert many questions for a single quiz. Quiz existence is verified once
 * up-front. Positions auto-increment from the current max if not provided,
 * keeping insert order deterministic.
 *
 * Per-row failures are captured (so a partial import still tells the caller
 * exactly which CSV rows didn't land) rather than aborting the whole batch
 * — matches the UX where the admin sees a preview and chooses to commit
 * everything that validated.
 */
export async function bulkCreateQuestions(
  quizId: string,
  inputs: BulkQuestionInput[],
  createdBy: string | null,
): Promise<BulkCreateQuestionsResult> {
  if (inputs.length === 0) {
    return { created: [], failures: [] };
  }
  if (inputs.length > 500) {
    throw new Error("bulkCreateQuestions accepts at most 500 rows per call.");
  }

  const supabase = getAdminSupabaseClient();

  const { data: quiz, error: quizErr } = await supabase
    .from("quizzes")
    .select("id")
    .eq("id", quizId)
    .maybeSingle();
  if (quizErr) {
    throw new Error(`Failed to verify quiz: ${quizErr.message}`);
  }
  if (!quiz) {
    throw new Error("Quiz not found for the supplied quizId.");
  }

  let nextPos = await nextQuestionPosition(quizId);

  const created: QuestionRecord[] = [];
  const failures: Array<{ index: number; message: string }> = [];

  for (let i = 0; i < inputs.length; i += 1) {
    const row = inputs[i];
    const position =
      row.position === undefined || row.position === null ? nextPos++ : row.position;

    const { data, error } = await supabase
      .from("questions")
      .insert({
        quiz_id: quizId,
        prompt: row.prompt,
        options: row.options,
        correct_index: row.correctIndex,
        explanation: row.explanation,
        clinical_area: row.clinicalArea,
        tags: row.tags,
        position,
        is_active: row.isActive,
        created_by: createdBy,
      })
      .select(QUESTION_COLUMNS)
      .single();

    if (error) {
      failures.push({ index: i, message: error.message });
      // If we used an auto-assigned slot, recycle it so the next row reuses it.
      if (row.position === undefined || row.position === null) {
        nextPos -= 1;
      }
      continue;
    }

    created.push(mapQuestion(data as QuestionRowDb));
  }

  return { created, failures };
}
