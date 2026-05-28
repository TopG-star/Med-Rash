import {
  extractBearerToken,
  verifyDeviceToken,
  type DeviceTokenClaims,
} from "./device-token";
import { HandlerEvent, HandlerResponse, jsonResponse } from "./http";

// Slice A2 phase 3c of docs/security-hardening-plan.md.
//
// Bearer-only. The legacy `x-medrash-gate-key` fallback that existed in
// Phase 1/2 was removed in 3a; the gate-key bootstrap on `/device-token`
// was removed in 3c and `_shared/gate.ts` was deleted. Bootstrap is now
// Cloudflare Turnstile + rate-limit (`_shared/turnstile.ts`,
// `_shared/rate-limit-bucket.ts`).

export type ParticipantAuthOk = {
  ok: true;
  method: "device-token";
  claims: DeviceTokenClaims;
};

export type ParticipantAuthErr = { ok: false; response: HandlerResponse };

export type ParticipantAuthResult = ParticipantAuthOk | ParticipantAuthErr;

export function requireParticipantAuth(event: HandlerEvent): ParticipantAuthResult {
  const bearer = extractBearerToken(event.headers);
  if (!bearer) {
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: "UNAUTHORIZED",
        message: "Missing device token. Mint one via /device-token.",
      }),
    };
  }

  const verified = verifyDeviceToken(bearer);
  if (!verified.ok) {
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: verified.code,
        message: "Device token rejected. Re-mint via /device-token.",
      }),
    };
  }

  return { ok: true, method: "device-token", claims: verified.claims };
}
