"use server";

import { revalidatePath } from "next/cache";

import {
  bulkCreateQuestions,
  createQuestionRecord,
  createQuizRecord,
  deactivateQuestionRecord,
  deactivateQuizRecord,
  parseCreateQuestionInput,
  parseCreateQuizInput,
  parseUpdateQuestionInput,
  parseUpdateQuizInput,
  updateQuestionRecord,
  updateQuizRecord,
  type BulkCreateQuestionsResult,
  type BulkQuestionInput,
  type QuestionRecord,
  type QuizRecord,
} from "@/lib/quiz-write";
import type { CsvQuestionDraft } from "@/lib/quiz-csv";

export type QuizActionResult<T> =
  | { ok: true; data: T }
  | { ok: false; message: string };

function fail(err: unknown, fallback: string): { ok: false; message: string } {
  return {
    ok: false,
    message: err instanceof Error ? err.message : fallback,
  };
}

/* ============================================================================
 * Quiz actions
 * ========================================================================== */

export async function createQuizAction(
  raw: Record<string, unknown>,
): Promise<QuizActionResult<QuizRecord>> {
  let parsed;
  try {
    parsed = parseCreateQuizInput(raw);
  } catch (err) {
    return fail(err, "Invalid quiz input.");
  }
  try {
    const quiz = await createQuizRecord(parsed);
    revalidatePath("/quiz-bank");
    return { ok: true, data: quiz };
  } catch (err) {
    return fail(err, "Failed to create quiz.");
  }
}

export async function updateQuizAction(
  raw: Record<string, unknown>,
): Promise<QuizActionResult<QuizRecord>> {
  let parsed;
  try {
    parsed = parseUpdateQuizInput(raw);
  } catch (err) {
    return fail(err, "Invalid quiz input.");
  }
  try {
    const quiz = await updateQuizRecord(parsed);
    revalidatePath("/quiz-bank");
    revalidatePath(`/quiz-bank/${quiz.slug}`);
    return { ok: true, data: quiz };
  } catch (err) {
    return fail(err, "Failed to update quiz.");
  }
}

export async function deactivateQuizAction(
  id: string,
  slug: string,
): Promise<QuizActionResult<QuizRecord>> {
  if (!id || !slug) {
    return { ok: false, message: "id and slug are required." };
  }
  try {
    const quiz = await deactivateQuizRecord(id);
    revalidatePath("/quiz-bank");
    revalidatePath(`/quiz-bank/${slug}`);
    return { ok: true, data: quiz };
  } catch (err) {
    return fail(err, "Failed to deactivate quiz.");
  }
}

/* ============================================================================
 * Question actions
 * ========================================================================== */

export async function createQuestionAction(
  raw: Record<string, unknown>,
  quizSlug: string,
): Promise<QuizActionResult<QuestionRecord>> {
  let parsed;
  try {
    parsed = parseCreateQuestionInput(raw);
  } catch (err) {
    return fail(err, "Invalid question input.");
  }
  try {
    const question = await createQuestionRecord(parsed);
    revalidatePath(`/quiz-bank/${quizSlug}`);
    revalidatePath("/quiz-bank");
    return { ok: true, data: question };
  } catch (err) {
    return fail(err, "Failed to create question.");
  }
}

export async function updateQuestionAction(
  raw: Record<string, unknown>,
  quizSlug: string,
): Promise<QuizActionResult<QuestionRecord>> {
  let parsed;
  try {
    parsed = parseUpdateQuestionInput(raw);
  } catch (err) {
    return fail(err, "Invalid question input.");
  }
  try {
    const question = await updateQuestionRecord(parsed);
    revalidatePath(`/quiz-bank/${quizSlug}`);
    return { ok: true, data: question };
  } catch (err) {
    return fail(err, "Failed to update question.");
  }
}

export async function deactivateQuestionAction(
  id: string,
  quizSlug: string,
): Promise<QuizActionResult<QuestionRecord>> {
  if (!id) {
    return { ok: false, message: "id is required." };
  }
  try {
    const question = await deactivateQuestionRecord(id);
    revalidatePath(`/quiz-bank/${quizSlug}`);
    return { ok: true, data: question };
  } catch (err) {
    return fail(err, "Failed to deactivate question.");
  }
}

/* ============================================================================
 * Bulk CSV import
 * ========================================================================== */

function draftsToBulkInputs(drafts: CsvQuestionDraft[]): BulkQuestionInput[] {
  return drafts.map((d) => ({
    prompt: d.prompt,
    options: d.options,
    correctIndex: d.correctIndex,
    explanation: d.explanation,
    clinicalArea: d.clinicalArea,
    tags: d.tags,
    position: d.position,
    isActive: d.isActive,
  }));
}

export async function importQuestionsAction(
  quizId: string,
  quizSlug: string,
  drafts: CsvQuestionDraft[],
): Promise<QuizActionResult<BulkCreateQuestionsResult>> {
  if (!quizId || !quizSlug) {
    return { ok: false, message: "quizId and quizSlug are required." };
  }
  if (!Array.isArray(drafts) || drafts.length === 0) {
    return { ok: false, message: "No rows to import." };
  }
  try {
    const result = await bulkCreateQuestions(quizId, draftsToBulkInputs(drafts));
    revalidatePath(`/quiz-bank/${quizSlug}`);
    revalidatePath("/quiz-bank");
    return { ok: true, data: result };
  } catch (err) {
    return fail(err, "Failed to import questions.");
  }
}
