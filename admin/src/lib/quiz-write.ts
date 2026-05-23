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

const SLUG_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$/;

/* ============================================================================
 * Parsing helpers
 * ========================================================================== */

function requireString(value: unknown, field: string, max = 5000): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${field} is required.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > max) {
    throw new Error(`${field} must be at most ${max} characters.`);
  }
  return trimmed;
}

function optionalString(value: unknown, field: string, max = 5000): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new Error(`${field} must be a string when provided.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > max) {
    throw new Error(`${field} must be at most ${max} characters.`);
  }
  return trimmed;
}

function parseInteger(value: unknown, field: string, min: number, max: number): number {
  const num =
    typeof value === "number"
      ? value
      : typeof value === "string" && value.trim().length > 0
        ? Number(value)
        : NaN;
  if (!Number.isInteger(num)) {
    throw new Error(`${field} must be an integer.`);
  }
  if (num < min || num > max) {
    throw new Error(`${field} must be between ${min} and ${max}.`);
  }
  return num;
}

function parseBoolean(value: unknown, fallback: boolean): boolean {
  if (typeof value === "boolean") return value;
  if (value === "true") return true;
  if (value === "false") return false;
  if (value === undefined || value === null || value === "") return fallback;
  throw new Error("Boolean field must be true|false.");
}

function parseSlug(value: unknown): string {
  const slug = requireString(value, "slug", 64).toLowerCase();
  if (!SLUG_PATTERN.test(slug)) {
    throw new Error(
      "slug must be lowercase alphanumeric with optional dashes (no leading/trailing dash, 1-64 chars).",
    );
  }
  return slug;
}

function parseOptions(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new Error("options must be an array of strings.");
  }
  if (value.length !== PILOT_QUESTION_OPTION_COUNT) {
    throw new Error(
      `options must contain exactly ${PILOT_QUESTION_OPTION_COUNT} entries for the pilot.`,
    );
  }
  const cleaned = value.map((raw, idx) => {
    if (typeof raw !== "string" || raw.trim().length === 0) {
      throw new Error(`options[${idx}] must be a non-empty string.`);
    }
    return raw.trim();
  });
  const unique = new Set(cleaned.map((s) => s.toLowerCase()));
  if (unique.size !== cleaned.length) {
    throw new Error("options must be unique (case-insensitive).");
  }
  return cleaned;
}

function parseTags(value: unknown): string[] {
  if (value === undefined || value === null || value === "") return [];
  let raw: unknown[];
  if (Array.isArray(value)) {
    raw = value;
  } else if (typeof value === "string") {
    raw = value
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
  } else {
    throw new Error("tags must be an array or comma-separated string.");
  }
  const cleaned: string[] = [];
  for (const entry of raw) {
    if (typeof entry !== "string") {
      throw new Error("each tag must be a string.");
    }
    const t = entry.trim().toLowerCase();
    if (t.length === 0) continue;
    if (t.length > 48) {
      throw new Error(`tag '${t}' exceeds 48 characters.`);
    }
    if (!cleaned.includes(t)) cleaned.push(t);
  }
  return cleaned;
}

function parseMetadata(value: unknown): Record<string, unknown> {
  if (value === undefined || value === null || value === "") return {};
  if (typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  throw new Error("metadata must be a JSON object when provided.");
}

/* ============================================================================
 * Input parsers
 * ========================================================================== */

export function parseCreateQuizInput(
  raw: Record<string, unknown>,
  createdBy: string | null,
): CreateQuizInput {
  return {
    slug: parseSlug(raw.slug),
    title: requireString(raw.title, "title", 160),
    category: requireString(raw.category, "category", 80),
    product: optionalString(raw.product, "product", 80),
    summary: requireString(raw.summary, "summary", 600),
    questionCountDefault: parseInteger(raw.questionCountDefault, "questionCountDefault", 1, 50),
    isActive: parseBoolean(raw.isActive, true),
    metadata: parseMetadata(raw.metadata),
    createdBy,
  };
}

export function parseUpdateQuizInput(raw: Record<string, unknown>): UpdateQuizInput {
  return {
    id: requireString(raw.id, "id", 64),
    title: requireString(raw.title, "title", 160),
    category: requireString(raw.category, "category", 80),
    product: optionalString(raw.product, "product", 80),
    summary: requireString(raw.summary, "summary", 600),
    questionCountDefault: parseInteger(raw.questionCountDefault, "questionCountDefault", 1, 50),
    isActive: parseBoolean(raw.isActive, true),
    metadata: parseMetadata(raw.metadata),
  };
}

export function parseCreateQuestionInput(
  raw: Record<string, unknown>,
  createdBy: string | null,
): CreateQuestionInput {
  const options = parseOptions(raw.options);
  const correctIndex = parseInteger(
    raw.correctIndex,
    "correctIndex",
    0,
    PILOT_QUESTION_OPTION_COUNT - 1,
  );
  return {
    quizId: requireString(raw.quizId, "quizId", 64),
    prompt: requireString(raw.prompt, "prompt", 1200),
    options,
    correctIndex,
    explanation: requireString(raw.explanation, "explanation", 1200),
    clinicalArea: optionalString(raw.clinicalArea, "clinicalArea", 120),
    tags: parseTags(raw.tags),
    position:
      raw.position === undefined || raw.position === null || raw.position === ""
        ? null
        : parseInteger(raw.position, "position", 0, 9999),
    isActive: parseBoolean(raw.isActive, true),
    createdBy,
  };
}

export function parseUpdateQuestionInput(raw: Record<string, unknown>): UpdateQuestionInput {
  const options = parseOptions(raw.options);
  const correctIndex = parseInteger(
    raw.correctIndex,
    "correctIndex",
    0,
    PILOT_QUESTION_OPTION_COUNT - 1,
  );
  return {
    id: requireString(raw.id, "id", 64),
    prompt: requireString(raw.prompt, "prompt", 1200),
    options,
    correctIndex,
    explanation: requireString(raw.explanation, "explanation", 1200),
    clinicalArea: optionalString(raw.clinicalArea, "clinicalArea", 120),
    tags: parseTags(raw.tags),
    position:
      raw.position === undefined || raw.position === null || raw.position === ""
        ? null
        : parseInteger(raw.position, "position", 0, 9999),
    isActive: parseBoolean(raw.isActive, true),
  };
}

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
      product: input.product,
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
      product: input.product,
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
