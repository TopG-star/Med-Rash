import type { z } from "zod";
import { validateBody } from "../../../src/lib/schemas/_helpers";
import { jsonResponse, type HandlerResponse } from "./http";

// Bridges the pure `validateBody` (admin/src/lib/schemas/_helpers.ts) into the
// Netlify handler error shape. On failure returns a 400 INVALID_INPUT with the
// historical `message` field (first issue) plus a structured `issues[]` array
// so newer clients can surface field-level errors without a contract bump.
export function validateOrRespond<T>(
  schema: z.ZodType<T>,
  payload: unknown,
): { ok: true; data: T } | { ok: false; response: HandlerResponse } {
  const result = validateBody(schema, payload);
  if (result.ok) {
    return { ok: true, data: result.data };
  }
  const firstMessage = result.issues[0]?.message ?? "Invalid request.";
  return {
    ok: false,
    response: jsonResponse(400, {
      ok: false,
      code: "INVALID_INPUT",
      message: firstMessage,
      issues: result.issues,
    }),
  };
}
