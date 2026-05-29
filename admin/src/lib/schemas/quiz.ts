import { z } from "zod";
import { metadataField, nonEmptyTrimmed, optionalTrimmedNullable } from "./_helpers";

const SLUG_RE = /^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$/;

export const quizSlugField = z.preprocess(
  (v) => (typeof v === "string" ? v.trim().toLowerCase() : v),
  z
    .string({ message: "slug is required." })
    .min(1, "slug is required.")
    .max(64, "slug is too long.")
    .regex(SLUG_RE, "slug must be lowercase alphanumeric with optional dashes."),
);

const booleanLoose = z
  .preprocess((v) => {
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v !== 0;
    if (typeof v === "string") {
      const t = v.trim().toLowerCase();
      if (["true", "1", "yes", "y", "active"].includes(t)) return true;
      if (["false", "0", "no", "n", "inactive"].includes(t)) return false;
    }
    return true;
  }, z.boolean())
  .optional()
  .default(true);

const questionCountField = z.preprocess((v) => {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? Math.floor(n) : v;
}, z
  .number()
  .int()
  .min(1, "questionCountDefault must be 1–50.")
  .max(50, "questionCountDefault must be 1–50."));

export const createQuizPayloadSchema = z.object({
  slug: quizSlugField,
  title: nonEmptyTrimmed("title", 160),
  category: nonEmptyTrimmed("category", 80),
  product: optionalTrimmedNullable(80),
  summary: nonEmptyTrimmed("summary", 600),
  questionCountDefault: questionCountField,
  isActive: booleanLoose,
  metadata: metadataField,
});

export const updateQuizPayloadSchema = createQuizPayloadSchema.extend({
  id: nonEmptyTrimmed("id", 64),
});

const optionsField = z
  .array(nonEmptyTrimmed("option", 400))
  .length(4, "options must contain exactly 4 entries.")
  .superRefine((opts, ctx) => {
    const seen = new Set<string>();
    for (const opt of opts) {
      const key = opt.toLowerCase();
      if (seen.has(key)) {
        ctx.addIssue({
          code: "custom",
          message: "options must be unique (case-insensitive).",
        });
        return;
      }
      seen.add(key);
    }
  });

const tagsField = z
  .preprocess((v) => {
    if (v === null || v === undefined) return [] as string[];
    const raw = Array.isArray(v) ? v : typeof v === "string" ? v.split(",") : [];
    const seen = new Set<string>();
    const out: string[] = [];
    for (const item of raw) {
      if (typeof item !== "string") continue;
      const trimmed = item.trim().toLowerCase();
      if (trimmed.length === 0 || trimmed.length > 48) continue;
      if (seen.has(trimmed)) continue;
      seen.add(trimmed);
      out.push(trimmed);
    }
    return out;
  }, z.array(z.string()))
  .optional()
  .default([]);

const correctIndexField = z.preprocess((v) => {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? Math.floor(n) : v;
}, z.number().int().min(0, "correctIndex must be 0–3.").max(3, "correctIndex must be 0–3."));

const positionField = z
  .preprocess((v) => {
    if (v === null || v === undefined) return null;
    const n = typeof v === "number" ? v : Number(v);
    return Number.isFinite(n) && n >= 0 ? Math.floor(n) : null;
  }, z.number().int().min(0).nullable())
  .optional();

export const createQuestionPayloadSchema = z.object({
  quizId: nonEmptyTrimmed("quizId", 64),
  prompt: nonEmptyTrimmed("prompt", 1200),
  options: optionsField,
  correctIndex: correctIndexField,
  explanation: nonEmptyTrimmed("explanation", 1200),
  clinicalArea: optionalTrimmedNullable(120),
  tags: tagsField,
  position: positionField,
  isActive: booleanLoose,
});

export const updateQuestionPayloadSchema = createQuestionPayloadSchema.extend({
  id: nonEmptyTrimmed("id", 64),
});

export const bulkCreateQuestionsPayloadSchema = z.object({
  quizId: nonEmptyTrimmed("quizId", 64),
  rows: z
    .array(z.record(z.string(), z.unknown()))
    .min(1, "rows must contain at least one row."),
});

export const deactivateByIdSchema = z.object({
  id: nonEmptyTrimmed("id", 64),
});

export const quizBankWriteSchema = z.discriminatedUnion("op", [
  z.object({ op: z.literal("create_quiz"), payload: createQuizPayloadSchema }),
  z.object({ op: z.literal("update_quiz"), payload: updateQuizPayloadSchema }),
  z.object({ op: z.literal("deactivate_quiz"), id: nonEmptyTrimmed("id", 64) }),
  z.object({ op: z.literal("create_question"), payload: createQuestionPayloadSchema }),
  z.object({ op: z.literal("update_question"), payload: updateQuestionPayloadSchema }),
  z.object({ op: z.literal("deactivate_question"), id: nonEmptyTrimmed("id", 64) }),
  z.object({ op: z.literal("bulk_create_questions"), payload: bulkCreateQuestionsPayloadSchema }),
]);

export type CreateQuizPayload = z.infer<typeof createQuizPayloadSchema>;
export type UpdateQuizPayload = z.infer<typeof updateQuizPayloadSchema>;
export type CreateQuestionPayload = z.infer<typeof createQuestionPayloadSchema>;
export type UpdateQuestionPayload = z.infer<typeof updateQuestionPayloadSchema>;
export type BulkCreateQuestionsPayload = z.infer<typeof bulkCreateQuestionsPayloadSchema>;
export type QuizBankWriteInput = z.infer<typeof quizBankWriteSchema>;
