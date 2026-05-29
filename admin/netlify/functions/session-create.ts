import { jsonResponse, parseJsonBody, requirePost, toV2Handler, HandlerEvent } from "./_shared/http";
import {
  requireAdminUserSession,
  requireLegacyWriteKey,
} from "./_shared/admin-user-session";
import { validateOrRespond } from "./_shared/validate";
import { createSessionSchema } from "../../src/lib/schemas/session";
import { getSupabaseAdminClient } from "./_shared/supabase";
import {
  createSessionRecord,
  type CreateSessionInput,
} from "../../src/lib/session-create";
import { logAdminAction } from "../../src/lib/audit";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

export async function handler(event: HandlerEvent) {
  const methodGuard = requirePost(event);
  if (methodGuard) return methodGuard;

  const legacyGuard = requireLegacyWriteKey(event);
  if (legacyGuard) return legacyGuard;

  const authResult = await requireAdminUserSession(event);
  if (!authResult.ok) return authResult.response;

  // A6 — per-admin bucket (30/60s). Session creation is rare; this caps
  // accidental loops in the dashboard from creating dozens of stale sessions.
  const supabaseEarly = getSupabaseAdminClient();
  const adminLimit = await enforceRateLimit(
    supabaseEarly,
    rateLimitConfig("session_create", authResult.auth.userId),
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

  // A7 — zod is the sole validator now. parseCreateSessionInput retired in P3.
  const validated = validateOrRespond(createSessionSchema, body);
  if (!validated.ok) return validated.response;

  const v = validated.data;
  const input: CreateSessionInput = {
    quizId: v.quizId,
    name: v.name,
    hostName: v.hostName ?? null,
    startsAt: v.startsAt ?? null,
    endsAt: v.endsAt ?? null,
    mode: v.mode,
    metadata: v.metadata ?? {},
    createdBy: authResult.auth.userId,
  };

  try {
    const result = await createSessionRecord(input);
    void logAdminAction(getSupabaseAdminClient(), {
      actorUserId: authResult.auth.userId,
      actorRole: authResult.auth.role,
      action: "session_create",
      targetType: "session",
      targetId: result.session.id,
      payload: input,
      metadata: { via: authResult.auth.via },
    });
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
