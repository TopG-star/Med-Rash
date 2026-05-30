"use server";

import { revalidatePath } from "next/cache";

import { requireAdminSession } from "@/lib/admin-session";
import {
  getQuizIdForQuestion,
  getQuizOwnerById,
} from "@/lib/quiz-detail-queries";
import {
  bulkCreateQuestions,
  createQuestionRecord,
  createQuizRecord,
  deactivateQuestionRecord,
  deactivateQuizRecord,
  updateQuestionRecord,
  updateQuizRecord,
  type BulkCreateQuestionsResult,
  type BulkQuestionInput,
  type CreateQuestionInput,
  type CreateQuizInput,
  type QuestionRecord,
  type QuizRecord,
  type UpdateQuestionInput,
  type UpdateQuizInput,
} from "@/lib/quiz-write";
import type { CsvQuestionDraft } from "@/lib/quiz-csv";
import { validateForAction } from "@/lib/schemas/_helpers";
import {
  createQuestionPayloadSchema,
  createQuizPayloadSchema,
  updateQuestionPayloadSchema,
  updateQuizPayloadSchema,
  type CreateQuestionPayload,
  type CreateQuizPayload,
  type UpdateQuestionPayload,
  type UpdateQuizPayload,
} from "@/lib/schemas/quiz";

export type QuizActionResult<T> =
  | { ok: true; data: T }
  | { ok: false; message: string };

function fail(err: unknown, fallback: string): { ok: false; message: string } {
  return {
    ok: false,
    message: err instanceof Error ? err.message : fallback,
  };
}

function toCreateQuizInput(
  v: CreateQuizPayload,
  createdBy: string | null,
): CreateQuizInput {
  return {
    slug: v.slug,
    title: v.title,
    category: v.category,
    product: v.product ?? null,
    summary: v.summary,
    questionCountDefault: v.questionCountDefault,
    isActive: v.isActive,
    metadata: v.metadata ?? {},
    createdBy,
  };
}

function toUpdateQuizInput(v: UpdateQuizPayload): UpdateQuizInput {
  return {
    id: v.id,
    title: v.title,
    category: v.category,
    product: v.product ?? null,
    summary: v.summary,
    questionCountDefault: v.questionCountDefault,
    isActive: v.isActive,
    metadata: v.metadata ?? {},
  };
}

function toCreateQuestionInput(
  v: CreateQuestionPayload,
  createdBy: string | null,
): CreateQuestionInput {
  return {
    quizId: v.quizId,
    prompt: v.prompt,
    options: v.options,
    correctIndex: v.correctIndex,
    explanation: v.explanation,
    clinicalArea: v.clinicalArea ?? null,
    tags: v.tags,
    position: v.position ?? null,
    isActive: v.isActive,
    createdBy,
  };
}

function toUpdateQuestionInput(v: UpdateQuestionPayload): UpdateQuestionInput {
  return {
    id: v.id,
    prompt: v.prompt,
    options: v.options,
    correctIndex: v.correctIndex,
    explanation: v.explanation,
    clinicalArea: v.clinicalArea ?? null,
    tags: v.tags,
    position: v.position ?? null,
    isActive: v.isActive,
  };
}

/**
 * Authorize a quiz mutation. Owners may mutate any quiz; Hosts may only
 * mutate quizzes whose `created_by` matches their user id. Used by the
 * Quiz Bank surface to enforce per-row ownership at the Server Action
 * boundary (defense in depth — the UI also hides Manage for non-owners).
 */
async function requireQuizMutationAllowed(quizId: string) {
  const session = await requireAdminSession({ currentPath: "/quiz-bank" });
  if (session.role === "owner") return session;
  const ownerId = await getQuizOwnerById(quizId);
  if (!ownerId) {
    throw new Error("Quiz not found.");
  }
  if (ownerId !== session.userId) {
    throw new Error("Hosts can only modify quizzes they created.");
  }
  return session;
}

/**
 * Same as {@link requireQuizMutationAllowed} but resolves the parent quiz
 * from a question id first (for question-level actions that only receive
 * a question UUID).
 */
async function requireQuestionMutationAllowed(questionId: string) {
  const session = await requireAdminSession({ currentPath: "/quiz-bank" });
  if (session.role === "owner") return session;
  const quizId = await getQuizIdForQuestion(questionId);
  if (!quizId) {
    throw new Error("Question not found.");
  }
  const ownerId = await getQuizOwnerById(quizId);
  if (!ownerId) {
    throw new Error("Parent quiz not found.");
  }
  if (ownerId !== session.userId) {
    throw new Error("Hosts can only modify questions on quizzes they created.");
  }
  return session;
}

/** Any signed-in admin (Owner or Host) can create a new quiz. */
async function requireAnyAdminSession() {
  return requireAdminSession({ currentPath: "/quiz-bank" });
}

/* ============================================================================
 * Quiz actions
 * ========================================================================== */

export async function createQuizAction(
  raw: Record<string, unknown>,
): Promise<QuizActionResult<QuizRecord>> {
  let session;
  try {
    session = await requireAnyAdminSession();
  } catch (err) {
    return fail(err, "Authorization failed.");
  }
  const validated = validateForAction(createQuizPayloadSchema, raw);
  if (!validated.ok) return { ok: false, message: validated.message };
  const parsed = toCreateQuizInput(validated.data, session.userId);
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
  const validated = validateForAction(updateQuizPayloadSchema, raw);
  if (!validated.ok) return { ok: false, message: validated.message };
  const parsed = toUpdateQuizInput(validated.data);
  try {
    await requireQuizMutationAllowed(parsed.id);
  } catch (err) {
    return fail(err, "Authorization failed.");
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
    await requireQuizMutationAllowed(id);
  } catch (err) {
    return fail(err, "Authorization failed.");
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
  const validated = validateForAction(createQuestionPayloadSchema, raw);
  if (!validated.ok) return { ok: false, message: validated.message };
  const parsed = toCreateQuestionInput(validated.data, null);
  let session;
  try {
    session = await requireQuizMutationAllowed(parsed.quizId);
  } catch (err) {
    return fail(err, "Authorization failed.");
  }
  try {
    const question = await createQuestionRecord({
      ...parsed,
      createdBy: session.userId,
    });
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
  const validated = validateForAction(updateQuestionPayloadSchema, raw);
  if (!validated.ok) return { ok: false, message: validated.message };
  const parsed = toUpdateQuestionInput(validated.data);
  try {
    await requireQuestionMutationAllowed(parsed.id);
  } catch (err) {
    return fail(err, "Authorization failed.");
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
    await requireQuestionMutationAllowed(id);
  } catch (err) {
    return fail(err, "Authorization failed.");
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
  let session;
  try {
    session = await requireQuizMutationAllowed(quizId);
  } catch (err) {
    return fail(err, "Authorization failed.");
  }
  try {
    const result = await bulkCreateQuestions(
      quizId,
      draftsToBulkInputs(drafts),
      session.userId,
    );
    revalidatePath(`/quiz-bank/${quizSlug}`);
    revalidatePath("/quiz-bank");
    return { ok: true, data: result };
  } catch (err) {
    return fail(err, "Failed to import questions.");
  }
}

/**
 * Result shape for the combined "create quiz + import CSV" action so the
 * caller can distinguish a partial import (quiz row created but some rows
 * failed) from a full failure (no quiz row at all).
 */
export type CreateQuizWithBulkResult = {
  quiz: QuizRecord;
  imported: number;
  failed: number;
  failures: Array<{ index: number; message: string }>;
};

/**
 * Single-shot bulk create: validates quiz metadata, creates the quiz row,
 * then bulk-imports the supplied CSV drafts. If the quiz row fails we
 * return early. If question inserts fail after the quiz row exists, we
 * return success with the partial counts so the UI can surface them and
 * route the admin to the detail page to retry the remaining rows.
 */
export async function createQuizWithBulkAction(
  rawPayload: Record<string, unknown>,
  drafts: CsvQuestionDraft[],
): Promise<QuizActionResult<CreateQuizWithBulkResult>> {
  let session;
  try {
    session = await requireAnyAdminSession();
  } catch (err) {
    return fail(err, "Authorization failed.");
  }
  const validated = validateForAction(createQuizPayloadSchema, rawPayload);
  if (!validated.ok) return { ok: false, message: validated.message };
  if (!Array.isArray(drafts) || drafts.length === 0) {
    return { ok: false, message: "Upload at least one valid CSV row before creating the quiz." };
  }
  const parsed = toCreateQuizInput(validated.data, session.userId);

  let quiz: QuizRecord;
  try {
    quiz = await createQuizRecord(parsed);
  } catch (err) {
    return fail(err, "Failed to create quiz.");
  }

  // Quiz row landed. Run the bulk import; surface partial-failure counts
  // rather than aborting — the admin can retry the failed rows on the
  // detail page via the standard CSV import panel.
  try {
    const result = await bulkCreateQuestions(
      quiz.id,
      draftsToBulkInputs(drafts),
      session.userId,
    );
    revalidatePath("/quiz-bank");
    revalidatePath(`/quiz-bank/${quiz.slug}`);
    return {
      ok: true,
      data: {
        quiz,
        imported: result.created.length,
        failed: result.failures.length,
        failures: result.failures,
      },
    };
  } catch (err) {
    // Quiz exists but bulk insert threw. Keep the quiz so the admin doesn't
    // lose their metadata work; surface the error and let them retry from
    // the detail page.
    revalidatePath("/quiz-bank");
    revalidatePath(`/quiz-bank/${quiz.slug}`);
    return {
      ok: true,
      data: {
        quiz,
        imported: 0,
        failed: drafts.length,
        failures: [
          {
            index: 0,
            message: err instanceof Error ? err.message : "Bulk import failed.",
          },
        ],
      },
    };
  }
}
