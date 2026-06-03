import { HandlerEvent, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
import {
  requireAdminUserSession,
  requireLegacyWriteKey,
} from "./_shared/admin-user-session";
import {
  hashRequestBody,
  readIdempotencyKey,
  withIdempotency,
  type HandlerResult,
} from "./_shared/idempotency";
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

  // P0.2 — idempotency. Re-running the same op with the same body returns
  // the cached 2xx so a Netlify retry / refresh / double-click doesn't
  // create two quizzes or insert a CSV batch twice. The op + payload are
  // both hashed so the same key cannot accidentally be reused across
  // different intents (returns 422 IDEMPOTENCY_KEY_REUSED).
  const idemKey = readIdempotencyKey(event.headers);
  const idemHash = hashRequestBody({ scope: "quiz_bank_write", data });

  const cached = await withIdempotency(
    getSupabaseAdminClient(),
    {
      scope: "quiz_bank_write",
      key: idemKey,
      requestHash: idemHash,
      actorUserId: createdBy,
    },
    async () => runQuizBankWrite(data, createdBy, authResult.auth.role, authResult.auth.via),
  );
  return jsonResponse(cached.statusCode, cached.body);
}

async function runQuizBankWrite(
  data: ReturnType<typeof quizBankWriteSchema.parse>,
  createdBy: string,
  actorRole: string,
  via: string,
): Promise<HandlerResult> {
  try {
    const auditClient = getSupabaseAdminClient();
    const actorMeta = { via };
    switch (data.op) {
      case "create_quiz": {
        const parsed = toCreateQuizInput(data.payload, createdBy);
        const quiz = await createQuizRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole,
          action: "create_quiz",
          targetType: "quiz",
          targetId: quiz.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return { statusCode: 201, body: { ok: true, quiz } };
      }
      case "update_quiz": {
        const parsed = toUpdateQuizInput(data.payload);
        const quiz = await updateQuizRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole,
          action: "update_quiz",
          targetType: "quiz",
          targetId: quiz.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return { statusCode: 200, body: { ok: true, quiz } };
      }
      case "deactivate_quiz": {
        const id = data.id;
        const quiz = await deactivateQuizRecord(id);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole,
          action: "deactivate_quiz",
          targetType: "quiz",
          targetId: id,
          metadata: actorMeta,
        });
        return { statusCode: 200, body: { ok: true, quiz } };
      }
      case "create_question": {
        const parsed = toCreateQuestionInput(data.payload, createdBy);
        const question = await createQuestionRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole,
          action: "create_question",
          targetType: "question",
          targetId: question.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return { statusCode: 201, body: { ok: true, question } };
      }
      case "update_question": {
        const parsed = toUpdateQuestionInput(data.payload);
        const question = await updateQuestionRecord(parsed);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole,
          action: "update_question",
          targetType: "question",
          targetId: question.id,
          payload: parsed,
          metadata: actorMeta,
        });
        return { statusCode: 200, body: { ok: true, question } };
      }
      case "deactivate_question": {
        const id = data.id;
        const question = await deactivateQuestionRecord(id);
        void logAdminAction(auditClient, {
          actorUserId: createdBy,
          actorRole,
          action: "deactivate_question",
          targetType: "question",
          targetId: id,
          metadata: actorMeta,
        });
        return { statusCode: 200, body: { ok: true, question } };
      }
      case "bulk_create_questions": {
        const quizId = data.payload.quizId;
        const rowsRaw = data.payload.rows;
        const { drafts, errors: rowErrors } = parseCsvQuestionRows(
          rowsRaw as CsvRowInput[],
        );
        if (drafts.length === 0) {
          return {
            statusCode: 400,
            body: {
              ok: false,
              code: "NO_VALID_ROWS",
              message: "No rows passed validation.",
              rowErrors,
            },
          };
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
          actorRole,
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
        return {
          statusCode: 201,
          body: {
            ok: true,
            createdCount: result.created.length,
            failures: result.failures,
            rowErrors,
          },
        };
      }
    }
    // Discriminated union should be exhaustive; this is unreachable.
    return {
      statusCode: 500,
      body: { ok: false, code: "QUIZ_WRITE_FAILED", message: "Unhandled op." },
    };
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
    return {
      statusCode: status,
      body: {
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
      },
    };
  }
}

export default toV2Handler(handler);
