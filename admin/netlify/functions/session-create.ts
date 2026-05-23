import { jsonResponse, parseJsonBody, requirePost, toV2Handler, HandlerEvent } from "./_shared/http";
import {
  requireAdminUserSession,
  requireLegacyWriteKey,
} from "./_shared/admin-user-session";
import {
  createSessionRecord,
  parseCreateSessionInput,
} from "../../src/lib/session-create";

export async function handler(event: HandlerEvent) {
  const methodGuard = requirePost(event);
  if (methodGuard) return methodGuard;

  const legacyGuard = requireLegacyWriteKey(event);
  if (legacyGuard) return legacyGuard;

  const authResult = await requireAdminUserSession(event);
  if (!authResult.ok) return authResult.response;

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

  let input;
  try {
    input = parseCreateSessionInput(body, authResult.auth.userId);
  } catch (err) {
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_INPUT",
      message: err instanceof Error ? err.message : "Invalid input.",
    });
  }

  try {
    const result = await createSessionRecord(input);
    return jsonResponse(201, {
      ok: true,
      session: result.session,
      joinUrl: result.joinUrl,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to create session.";
    const isNotFound = /not found/i.test(message);
    const isConflict = /unique join code|inactive quiz/i.test(message);
    return jsonResponse(isNotFound ? 404 : isConflict ? 409 : 500, {
      ok: false,
      code: isNotFound
        ? "QUIZ_NOT_FOUND"
        : isConflict
          ? "SESSION_CONFLICT"
          : "SESSION_CREATE_FAILED",
      message,
    });
  }
}

export default toV2Handler(handler);
