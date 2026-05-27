import {
  extractBearerToken,
  verifyDeviceToken,
  type DeviceTokenClaims,
} from "./device-token";
import { HandlerEvent, HandlerResponse, jsonResponse } from "./http";
import { requireGateAuthorization } from "./gate";

// Slice A2 of docs/security-hardening-plan.md.
//
// Single source of truth for participant-side authorization. Replaces the
// direct `requireGateAuthorization` calls so every endpoint accepts both
// auth methods during the transition window:
//
//   1. Preferred:  Authorization: Bearer <device-token>     (Slice A2)
//   2. Fallback:   x-medrash-gate-key: <static>             (legacy)
//
// The fallback is on by default during Phase 1 (backend) so live Flutter
// builds keep working. Set MEDRASH_GATE_KEY_FALLBACK=false in Netlify env
// to flip the kill-switch once Phase 2 (Flutter rollout) has had one full
// pilot session of mileage, then delete _shared/gate.ts in Phase 3.

export type ParticipantAuthOk =
  | { ok: true; method: "device-token"; claims: DeviceTokenClaims }
  | { ok: true; method: "legacy-gate-key"; claims: null };

export type ParticipantAuthErr = { ok: false; response: HandlerResponse };

export type ParticipantAuthResult = ParticipantAuthOk | ParticipantAuthErr;

function isFallbackEnabled(): boolean {
  // Default to enabled — the only safe default while real participant
  // traffic is still on the legacy header. Opt-out is explicit so a typo
  // in the env can never lock everyone out.
  const raw = process.env.MEDRASH_GATE_KEY_FALLBACK?.trim().toLowerCase();
  if (raw === "false" || raw === "0" || raw === "off" || raw === "no") {
    return false;
  }
  return true;
}

export function requireParticipantAuth(event: HandlerEvent): ParticipantAuthResult {
  const bearer = extractBearerToken(event.headers);
  if (bearer) {
    const verified = verifyDeviceToken(bearer);
    if (verified.ok) {
      return { ok: true, method: "device-token", claims: verified.claims };
    }

    // A bearer was supplied but failed validation. Do NOT silently fall
    // back to the gate key — the client clearly intended bearer auth, so
    // returning 401 surfaces the real failure mode (expired, tampered,
    // wrong secret) instead of masking it behind a stale shared key.
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: verified.code,
        message: "Device token rejected. Re-mint via /device-token.",
      }),
    };
  }

  if (isFallbackEnabled()) {
    const legacy = requireGateAuthorization(event);
    if (legacy === null) {
      return { ok: true, method: "legacy-gate-key", claims: null };
    }
    return { ok: false, response: legacy };
  }

  return {
    ok: false,
    response: jsonResponse(401, {
      ok: false,
      code: "UNAUTHORIZED",
      message: "Missing or invalid device token.",
    }),
  };
}
