import { HandlerEvent, HandlerResponse, jsonResponse } from "./http";

/**
 * Gate for admin WRITE operations (session-create, quiz-write, etc.).
 *
 * Separate from `requireGateAuthorization` (which protects read-side participant
 * endpoints) so the two secrets can be rotated independently and a leak of one
 * does not grant write access to admin state.
 *
 * Header: `x-medrash-admin-write-key`
 * Env:    `MEDRASH_ADMIN_WRITE_KEY`
 */
export function requireAdminWriteAuthorization(
  event: HandlerEvent,
): HandlerResponse | null {
  const expected = process.env.MEDRASH_ADMIN_WRITE_KEY?.trim();
  if (!expected) {
    return jsonResponse(500, {
      ok: false,
      code: "ADMIN_WRITE_KEY_NOT_CONFIGURED",
      message: "MEDRASH_ADMIN_WRITE_KEY is not configured.",
    });
  }

  const headers = event.headers ?? {};
  let incoming = "";
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === "x-medrash-admin-write-key" && typeof value === "string") {
      incoming = value;
      break;
    }
  }

  if (!incoming || incoming.trim() !== expected) {
    return jsonResponse(401, {
      ok: false,
      code: "UNAUTHORIZED_ADMIN_WRITE",
      message: "Unauthorized admin write request.",
    });
  }

  return null;
}
