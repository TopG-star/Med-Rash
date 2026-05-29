import { HandlerEvent, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
import {
  requireAdminUserSession,
  requireLegacyWriteKey,
} from "./_shared/admin-user-session";
import { validateOrRespond } from "./_shared/validate";
import {
  quizBankWriteSchema,
  type CreateQuestionPayload,
  type CreateQuizPayload,
  type UpdateQuestionPayload,
  type UpdateQuizPayload,
} from "../../src/lib/schemas/quiz";
import { getSupabaseAdminClient } from "./_shared/supabase";
import {
  bulkCreateQuestions,
  createQuestionRecord,
  createQuizRecord,
  deactivateQuestionRecord,
  deactivateQuizRecord,
  updateQuestionRecord,
  updateQuizRecord,
  type BulkQuestionInput,
  type CreateQuestionInput,
  type CreateQuizInput,
  type UpdateQuestionInput,
  type UpdateQuizInput,
} from "../../src/lib/quiz-write";
import { parseCsvQuestionRows, type CsvRowInput } from "../../src/lib/quiz-csv";
import { logAdminAction } from "../../src/lib/audit";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

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

export async function handler(event: HandlerEvent) {
  const methodGuard = requirePost(event);
  if (methodGuard) return methodGuard;

  const legacyGuard = requireLegacyWriteKey(event);
  if (legacyGuard) return legacyGuard;

  const authResult = await requireAdminUserSession(event);
  if (!authResult.ok) return authResult.response;
  if (authResult.auth.role !== "owner") {
    return jsonResponse(403, {
      ok: false,
      code: "FORBIDDEN_OWNER_ONLY",
      message: "Only Owners can edit the quiz bank.",
    });
  }
  const createdBy = authResult.auth.userId;

  // A6 — per-admin bucket (30/60s). Bulk CSV imports happen, but never at
  // 30/min from a single admin — that signals automation or a stuck client.
  const auditClientEarly = getSupabaseAdminClient();
  const adminLimit = await enforceRateLimit(
    auditClientEarly,
    rateLimitConfig("quiz_bank_write", createdBy),
  );
  if (!adminLimit.allowed) {
    return jsonResponse(429, {
      ok: false,
      code: "RATE_LIMITED",
      message: formatLockoutMessage(adminLimit),
      retryAfterSeconds: adminLimit.retryAfterSeconds,
    });
  }

  let body: Record<string, unknown>;
  try {
    body = parseJsonBody(event);
  } catch (err) {
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_JSON_BODY",
      message: err instanceof Error ? err.message : "Invalid request body.",
    });
  }

  // A7 — zod discriminated-union is the sole validator now. parseCreate*/parseUpdate*
  // were retired in P3; per-op payloads are typed via the discriminated union.
  const validated = validateOrRespond(quizBankWriteSchema, body);
  if (!validated.ok) return validated.response;
  const data = validated.data;

  try {
    const auditClient = getSupabaseAdminClient();
    const actorMeta = { via: authResult.auth.via };
    switch (data.op) {
      case "create_quiz": {
        const parsed = toCreateQuizInput(data.payload, createdBy);
        const quiz = await createQuizRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole: authResult.auth.role,
          action: "create_quiz",
          targetType: "quiz",
          targetId: quiz.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return jsonResponse(201, { ok: true, quiz });
      }
      case "update_quiz": {
        const parsed = toUpdateQuizInput(data.payload);
        const quiz = await updateQuizRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole: authResult.auth.role,
          action: "update_quiz",
          targetType: "quiz",
          targetId: quiz.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return jsonResponse(200, { ok: true, quiz });
      }
      case "deactivate_quiz": {
        const id = data.id;
        const quiz = await deactivateQuizRecord(id);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole: authResult.auth.role,
          action: "deactivate_quiz",
          targetType: "quiz",
          targetId: id,
          metadata: actorMeta,
        });
        return jsonResponse(200, { ok: true, quiz });
      }
      case "create_question": {
        const parsed = toCreateQuestionInput(data.payload, createdBy);
        const question = await createQuestionRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole: authResult.auth.role,
          action: "create_question",
          targetType: "question",
          targetId: question.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return jsonResponse(201, { ok: true, question });
      }
      case "update_question": {
        const parsed = toUpdateQuestionInput(data.payload);
        const question = await updateQuestionRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole: authResult.auth.role,
          action: "update_question",
          targetType: "question",
          targetId: question.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return jsonResponse(200, { ok: true, question });
      }
      case "deactivate_question": {
        const id = data.id;
        const question = await deactivateQuestionRecord(id);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole: authResult.auth.role,
          action: "deactivate_question",
          targetType: "question",
          targetId: id,
          metadata: actorMeta,
        });
        return jsonResponse(200, { ok: true, question });
      }
      case "bulk_create_questions": {
        const quizId = data.payload.quizId;
        const rowsRaw = data.payload.rows;
        const { drafts, errors: rowErrors } = parseCsvQuestionRows(
          rowsRaw as CsvRowInput[],
        );
        if (drafts.length === 0) {
          return jsonResponse(400, {
            ok: false,
            code: "NO_VALID_ROWS",
            message: "No rows passed validation.",
            rowErrors,
          });
        }
        const inputs: BulkQuestionInput[] = drafts.map((d) => ({
          prompt: d.prompt,
          options: d.options,
          correctIndex: d.correctIndex,
          explanation: d.explanation,
          clinicalArea: d.clinicalArea,
          tags: d.tags,
          position: d.position,
          isActive: d.isActive,
        }));
        const result = await bulkCreateQuestions(quizId, inputs, createdBy);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole: authResult.auth.role,
          action: "bulk_create_questions",
          targetType: "quiz",
          targetId: quizId,
          metadata: {
            ...actorMeta,
            createdCount: result.created.length,
            failureCount: result.failures.length,
            rowErrorCount: rowErrors.length,
          },
        });
        return jsonResponse(201, {
          ok: true,
          createdCount: result.created.length,
          failures: result.failures,
          rowErrors,
        });
      }
    }
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Quiz Bank write failed.";
    const lower = message.toLowerCase();
    const status = /not found/.test(lower)
      ? 404
      : /already in use|inactive|unique/.test(lower)
        ? 409
        : /required|must be|invalid|exceeds/.test(lower)
          ? 400
          : 500;
    return jsonResponse(status, {
      ok: false,
      code:
        status === 404
          ? "NOT_FOUND"
          : status === 409
            ? "CONFLICT"
            : status === 400
              ? "INVALID_INPUT"
              : "QUIZ_WRITE_FAILED",
      message,
    });
  }
}

export default toV2Handler(handler);
