import { mintDeviceToken } from "./_shared/device-token";
import { requireGateAuthorization } from "./_shared/gate";
import {
  HandlerEvent,
  HandlerResponse,
  handlePreflight,
  jsonResponse,
  parseJsonBody,
  requirePost,
  toV2Handler,
} from "./_shared/http";
import { consume } from "./_shared/rate-limit-bucket";
import { extractRemoteIp, verifyTurnstileToken } from "./_shared/turnstile";

// Slice A2 — mint a per-device bearer token.
//
// Phase 3b auth model (this commit) — **dual-path bootstrap**:
//
//   1. Preferred:  `turnstileToken` field in JSON body. Verified against
//      Cloudflare siteverify (`_shared/turnstile.ts`). Per-(ip, device)
//      rate-limit applied (`_shared/rate-limit-bucket.ts`). If the token
//      is present but fails verification, we return 401 immediately —
//      same strict-then-fallback ordering as `participant-auth.ts`.
//   2. Fallback:   legacy `x-medrash-gate-key` header. Kept for the one
//      deploy window where live Flutter builds may not yet ship the
//      Turnstile widget. Phase 3c removes this branch + deletes
//      `_shared/gate.ts`.
//
// Request:  POST { deviceInstallId: string, participantId?: string,
//                  turnstileToken?: string }
// Response: { ok: true, token, issuedAt, expiresAt, refreshAfter }
//
// Rate-limit response (429):
//   { ok: false, code: 'RATE_LIMITED', retryAfterSeconds }
export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) {
    return preflight;
  }

  const methodResponse = requirePost(event);
  if (methodResponse) {
    return methodResponse;
  }

  let body: Record<string, unknown>;
  try {
    body = parseJsonBody(event);
  } catch (error) {
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: error instanceof Error ? error.message : "Invalid request body.",
    });
  }

  const deviceInstallId =
    typeof body.deviceInstallId === "string" ? body.deviceInstallId.trim() : "";
  const participantIdRaw =
    typeof body.participantId === "string" ? body.participantId.trim() : "";
  const turnstileTokenRaw =
    typeof body.turnstileToken === "string" ? body.turnstileToken.trim() : "";

  if (!deviceInstallId) {
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: "deviceInstallId is required.",
    });
  }

  // ---- Bootstrap auth ----------------------------------------------------
  const remoteIp = extractRemoteIp(event.headers);

  if (turnstileTokenRaw.length > 0) {
    // Path A — Turnstile + rate-limit. Strict: a present-but-invalid token
    // does NOT silently fall back to the gate key.
    const limit = consume(`${remoteIp ?? "anon"}::${deviceInstallId}`);
    if (!limit.allowed) {
      return {
        statusCode: 429,
        headers: {
          "content-type": "application/json",
          "cache-control": "no-store",
          "retry-after": String(limit.retryAfterSeconds),
        },
        body: JSON.stringify({
          ok: false,
          code: "RATE_LIMITED",
          retryAfterSeconds: limit.retryAfterSeconds,
        }),
      };
    }

    const verified = await verifyTurnstileToken(turnstileTokenRaw, remoteIp);
    if (!verified.ok) {
      return jsonResponse(401, {
        ok: false,
        code: "TURNSTILE_REJECTED",
        message:
          verified.errorMessage ??
          "Cloudflare Turnstile token verification failed.",
        errorCodes: verified.errorCodes,
      });
    }
  } else {
    // Path B — legacy gate-key fallback (Phase 3b transition only).
    const gateResponse = requireGateAuthorization(event);
    if (gateResponse) {
      return gateResponse;
    }
  }

  // ---- Mint ---------------------------------------------------------------
  try {
    const minted = mintDeviceToken({
      deviceInstallId,
      participantId: participantIdRaw.length > 0 ? participantIdRaw : null,
    });
    return jsonResponse(200, {
      ok: true,
      token: minted.token,
      issuedAt: minted.issuedAt,
      expiresAt: minted.expiresAt,
      refreshAfter: minted.refreshAfter,
    });
  } catch (error) {
    return jsonResponse(500, {
      ok: false,
      code: "DEVICE_TOKEN_MINT_FAILED",
      message:
        error instanceof Error
          ? error.message
          : "Could not mint a device token.",
    });
  }
}

export default toV2Handler(handler);
