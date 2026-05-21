import { HandlerEvent, jsonResponse, parseJsonBody, requirePost, toV2Handler } from "./_shared/http";
import { requireAdminWriteAuthorization } from "./_shared/admin-gate";
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

  const authGuard = requireAdminWriteAuthorization(event);
  if (authGuard) return authGuard;

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
    switch (op) {
      case "create_quiz": {
        const parsed = parseCreateQuizInput(payload!);
        const quiz = await createQuizRecord(parsed);
        return jsonResponse(201, { ok: true, quiz });
      }
      case "update_quiz": {
        const parsed = parseUpdateQuizInput(payload!);
        const quiz = await updateQuizRecord(parsed);
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
        return jsonResponse(200, { ok: true, quiz });
      }
      case "create_question": {
        const parsed = parseCreateQuestionInput(payload!);
        const question = await createQuestionRecord(parsed);
        return jsonResponse(201, { ok: true, question });
      }
      case "update_question": {
        const parsed = parseUpdateQuestionInput(payload!);
        const question = await updateQuestionRecord(parsed);
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
        const result = await bulkCreateQuestions(quizId, inputs);
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
