import { HandlerEvent, HandlerResponse, jsonResponse } from "./http";

export function requireGateAuthorization(event: HandlerEvent): HandlerResponse | null {
  const expected = process.env.MEDRASH_GATE_API_KEY?.trim();
  if (!expected) {
    return jsonResponse(500, {
      ok: false,
      code: "GATE_KEY_NOT_CONFIGURED",
      message: "MEDRASH_GATE_API_KEY is not configured.",
    });
  }

  const incoming =
    event.headers?.["x-medrash-gate-key"] ??
    event.headers?.["X-MEDRASH-GATE-KEY"] ??
    "";

  if (!incoming || incoming.trim() !== expected) {
    return jsonResponse(401, {
      ok: false,
      code: "UNAUTHORIZED_GATE",
      message: "Unauthorized gate request.",
    });
  }

  return null;
}

