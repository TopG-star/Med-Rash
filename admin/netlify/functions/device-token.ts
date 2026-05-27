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

// Slice A2 — mint a per-device bearer token.
//
// Authorization model during the transition:
//   Phase 1 (this commit): bootstrap is gated by the legacy
//     MEDRASH_GATE_API_KEY header. The whole purpose of A2 is to retire
//     that key, but for one release window we keep it as the bootstrap
//     trust anchor so Flutter can switch to bearer tokens incrementally.
//   Phase 2: Flutter ships a build that calls this endpoint on first
//     launch and re-mints proactively before exp - 1h.
//   Phase 3: replace the gate-key bootstrap here with Turnstile/hCaptcha
//     (or an attestation challenge), then delete _shared/gate.ts.
//
// Request:  POST { deviceInstallId: string, participantId?: string }
// Response: { ok: true, token: string, issuedAt: number, expiresAt: number,
//             refreshAfter: number }
//
// `issuedAt`, `expiresAt`, `refreshAfter` are unix seconds. The client is
// expected to re-call this endpoint once `now >= refreshAfter` to obtain a
// fresh token; doing so resets the 24h sliding window.
export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) {
    return preflight;
  }

  const methodResponse = requirePost(event);
  if (methodResponse) {
    return methodResponse;
  }

  const gateResponse = requireGateAuthorization(event);
  if (gateResponse) {
    return gateResponse;
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

  if (!deviceInstallId) {
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: "deviceInstallId is required.",
    });
  }

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
