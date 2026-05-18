import { HandlerEvent, jsonResponse, parseJsonBody, requirePost } from "./_shared/http";
import { requireAdminWriteAuthorization } from "./_shared/admin-gate";
import {
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
} from "../../src/lib/quiz-write";

type Operation =
  | "create_quiz"
  | "update_quiz"
  | "deactivate_quiz"
  | "create_question"
  | "update_question"
  | "deactivate_question";

const SUPPORTED_OPS: ReadonlySet<Operation> = new Set([
  "create_quiz",
  "update_quiz",
  "deactivate_quiz",
  "create_question",
  "update_question",
  "deactivate_question",
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
