import { z } from "zod";
import { identityInputSchema } from "./identity";
import { nonEmptyTrimmed, optionalTrimmedNullable } from "./_helpers";

const MAX_TIME_MS = 2 * 60 * 60 * 1000;

const selectedIndexField = z.preprocess((v) => {
  if (typeof v === "number") return Math.floor(v);
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? Math.floor(n) : v;
  }
  return v;
}, z.number().int().min(0, "selectedIndex must be >= 0."));

const responseTimeField = z
  .preprocess((v) => {
    if (v === null || v === undefined) return 0;
    const n = typeof v === "number" ? v : Number(v);
    return Number.isFinite(n) ? Math.max(0, Math.floor(n)) : 0;
  }, z.number().int().min(0))
  .optional();

const scoreField = z.preprocess((v) => {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? Math.max(0, Math.floor(n)) : 0;
}, z.number().int().min(0));

const totalQuestionsField = z.preprocess((v) => {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) && n > 0 ? Math.max(1, Math.floor(n)) : 5;
}, z.number().int().min(1));

const timeTakenField = z.preprocess((v) => {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.min(MAX_TIME_MS, Math.max(0, Math.floor(n)));
}, z.number().int().min(0).max(MAX_TIME_MS));

export const attemptAnswerSchema = z.object({
  questionId: nonEmptyTrimmed("questionId", 128),
  selectedIndex: selectedIndexField,
  selectedOptionText: z.string().optional(),
  isCorrect: z.boolean().optional(),
  responseTimeMs: responseTimeField,
});

export const attemptSubmitSchema = identityInputSchema
  .extend({
    quizId: nonEmptyTrimmed("quizId", 128),
    mode: z.enum(["learning", "ranked"]).optional().default("learning"),
    origin: z.enum(["qr_session", "open_access"]).optional().default("open_access"),
    sessionId: optionalTrimmedNullable(64),
    score: scoreField,
    totalQuestions: totalQuestionsField,
    timeTakenMs: timeTakenField,
    answers: z.array(attemptAnswerSchema).max(500, "Too many answers."),
  })
  .superRefine((value, ctx) => {
    if (value.origin === "qr_session" && !value.sessionId) {
      ctx.addIssue({
        code: "custom",
        path: ["sessionId"],
        message: "sessionId is required when origin is qr_session.",
      });
    }
  });

export type AttemptSubmitInput = z.infer<typeof attemptSubmitSchema>;
export type AttemptAnswerInput = z.infer<typeof attemptAnswerSchema>;
