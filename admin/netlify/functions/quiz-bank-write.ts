import { HandlerEvent, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
import {
  requireAdminUserSession,
  requireLegacyWriteKey,
} from "./_shared/admin-user-session";
import { validateOrRespond } from "./_shared/validate";
import { quizBankWriteSchema } from "../../src/lib/schemas/quiz";
import { getSupabaseAdminClient } from "./_shared/supabase";
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
  type BulkQuestionInput,
} from "../../src/lib/quiz-write";
import { parseCsvQuestionRows, type CsvRowInput } from "../../src/lib/quiz-csv";
import { logAdminAction } from "../../src/lib/audit";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

type Operation =
  | "create_quiz"
  | "update_quiz"
  | "deactivate_quiz"
  | "create_question"
  | "update_question"
  | "deactivate_question"
  | "bulk_create_questions";

const SUPPORTED_OPS: ReadonlySet<Operation> = new Set([
  "create_quiz",
  "update_quiz",
  "deactivate_quiz",
  "create_question",
  "update_question",
  "deactivate_question",
  "bulk_create_questions",
]);

function isOperation(value: unknown): value is Operation {
  return typeof value === "string" && SUPPORTED_OPS.has(value as Operation);
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

  // A7 — zod discriminated-union front door. Catches malformed op, missing
  // payload, wrong payload shape, etc. with structured issues[]. The shared
  // parseCreate*/parseUpdate* below still apply normalization + fallbacks.
  const validated = validateOrRespond(quizBankWriteSchema, body);
  if (!validated.ok) return validated.response;

  const op = body.op;
  if (!isOperation(op)) {
    return jsonResponse(400, {
      ok: false,
      code: "UNSUPPORTED_OP",
      message: `op must be one of: ${Array.from(SUPPORTED_OPS).join(", ")}.`,
    });
  }

  const payload =
    body.payload && typeof body.payload === "object" && !Array.isArray(body.payload)
      ? (body.payload as Record<string, unknown>)
      : null;

  if (!payload && op !== "deactivate_quiz" && op !== "deactivate_question") {
    return jsonResponse(400, {
      ok: false,
      code: "MISSING_PAYLOAD",
      message: "payload is required for this op.",
    });
  }

  try {
    const auditClient = getSupabaseAdminClient();
    const actorMeta = { via: authResult.auth.via };
    switch (op) {
      case "create_quiz": {
        const parsed = parseCreateQuizInput(payload!, createdBy);
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
        const parsed = parseUpdateQuizInput(payload!);
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
        const id = typeof body.id === "string" ? body.id : "";
        if (!id) {
          return jsonResponse(400, {
            ok: false,
            code: "MISSING_ID",
            message: "id is required.",
          });
        }
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
        const parsed = parseCreateQuestionInput(payload!, createdBy);
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
        const parsed = parseUpdateQuestionInput(payload!);
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
        const id = typeof body.id === "string" ? body.id : "";
        if (!id) {
          return jsonResponse(400, {
            ok: false,
            code: "MISSING_ID",
            message: "id is required.",
          });
        }
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
        const quizId = typeof payload!.quizId === "string" ? payload!.quizId : "";
        if (!quizId) {
          return jsonResponse(400, {
            ok: false,
            code: "MISSING_QUIZ_ID",
            message: "payload.quizId is required.",
          });
        }
        const rowsRaw = payload!.rows;
        if (!Array.isArray(rowsRaw)) {
          return jsonResponse(400, {
            ok: false,
            code: "INVALID_INPUT",
            message: "payload.rows must be an array of CSV row objects.",
          });
        }
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
