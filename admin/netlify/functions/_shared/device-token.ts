import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

// Slice A2 of docs/security-hardening-plan.md.
//
// Per-device HMAC-signed bearer token. Replaces the static
// MEDRASH_GATE_API_KEY shared across every Flutter participant build.
//
// Wire format (compact, JWT-ish but trimmed):
//   `${base64url(payloadJsonString)}.${base64url(signature)}`
//
// Payload (decoded JSON):
//   { v: 1, did: string, pid: string|null, iat: number, exp: number, n: string }
//   - did = deviceInstallId (UUID minted on first launch, never rotates)
//   - pid = participantId   (app.users.id once the device has been bound;
//                            null during the bootstrap window before profile
//                            creation, which is fine — the token still
//                            authenticates the device)
//   - iat = issued-at, unix seconds
//   - exp = expires-at, unix seconds (24h sliding by client behaviour)
//   - n   = 8-byte hex nonce so two tokens minted in the same second differ
//
// Signature: HMAC-SHA256(MEDRASH_DEVICE_TOKEN_SECRET, payloadB64Url)

export const DEVICE_TOKEN_VERSION = 1 as const;
export const DEVICE_TOKEN_TTL_SECONDS = 24 * 60 * 60;
// Client should refresh once the remaining lifetime drops below this. The
// /device-token endpoint is idempotent so a refresh = a fresh mint.
export const DEVICE_TOKEN_REFRESH_BEFORE_SECONDS = 60 * 60;

export type DeviceTokenClaims = {
  version: number;
  deviceInstallId: string;
  participantId: string | null;
  issuedAt: number;
  expiresAt: number;
  nonce: string;
};

export type DeviceTokenVerifyOk = { ok: true; claims: DeviceTokenClaims };
export type DeviceTokenVerifyErr = {
  ok: false;
  code:
    | "DEVICE_TOKEN_MISSING"
    | "DEVICE_TOKEN_MALFORMED"
    | "DEVICE_TOKEN_BAD_SIGNATURE"
    | "DEVICE_TOKEN_EXPIRED"
    | "DEVICE_TOKEN_VERSION_MISMATCH"
    | "DEVICE_TOKEN_SECRET_MISSING";
};
export type DeviceTokenVerifyResult = DeviceTokenVerifyOk | DeviceTokenVerifyErr;

export type MintInput = {
  deviceInstallId: string;
  participantId?: string | null;
  ttlSeconds?: number;
  nowMs?: number;
};

export type MintedDeviceToken = {
  token: string;
  issuedAt: number;
  expiresAt: number;
  refreshAfter: number;
};

function readSecret(): string | null {
  const raw = process.env.MEDRASH_DEVICE_TOKEN_SECRET?.trim();
  if (!raw || raw.length < 32) {
    return null;
  }
  return raw;
}

function base64UrlEncode(bytes: Buffer): string {
  return bytes
    .toString("base64")
    .replace(/=+$/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function base64UrlDecode(value: string): Buffer {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
  return Buffer.from(padded + pad, "base64");
}

function signPayload(payloadB64: string, secret: string): Buffer {
  return createHmac("sha256", secret).update(payloadB64).digest();
}

export function mintDeviceToken(input: MintInput): MintedDeviceToken {
  const secret = readSecret();
  if (!secret) {
    throw new Error(
      "MEDRASH_DEVICE_TOKEN_SECRET must be configured (>= 32 chars).",
    );
  }

  const deviceInstallId = input.deviceInstallId?.trim() ?? "";
  if (!deviceInstallId) {
    throw new Error("mintDeviceToken: deviceInstallId is required.");
  }

  const nowSec = Math.floor((input.nowMs ?? Date.now()) / 1000);
  const ttl =
    input.ttlSeconds && input.ttlSeconds > 0
      ? input.ttlSeconds
      : DEVICE_TOKEN_TTL_SECONDS;
  const exp = nowSec + ttl;
  const nonce = randomBytes(8).toString("hex");

  const payload = {
    v: DEVICE_TOKEN_VERSION,
    did: deviceInstallId,
    pid: input.participantId ? input.participantId.trim() : null,
    iat: nowSec,
    exp,
    n: nonce,
  };

  const payloadB64 = base64UrlEncode(Buffer.from(JSON.stringify(payload), "utf8"));
  const sigB64 = base64UrlEncode(signPayload(payloadB64, secret));

  return {
    token: `${payloadB64}.${sigB64}`,
    issuedAt: nowSec,
    expiresAt: exp,
    refreshAfter: Math.max(nowSec, exp - DEVICE_TOKEN_REFRESH_BEFORE_SECONDS),
  };
}

export function verifyDeviceToken(
  rawToken: string | null | undefined,
  options: { nowMs?: number } = {},
): DeviceTokenVerifyResult {
  const secret = readSecret();
  if (!secret) {
    return { ok: false, code: "DEVICE_TOKEN_SECRET_MISSING" };
  }
  if (!rawToken || typeof rawToken !== "string" || rawToken.length === 0) {
    return { ok: false, code: "DEVICE_TOKEN_MISSING" };
  }

  const parts = rawToken.split(".");
  if (parts.length !== 2) {
    return { ok: false, code: "DEVICE_TOKEN_MALFORMED" };
  }

  const [payloadB64, sigB64] = parts;
  let payloadJson: string;
  let payload: {
    v?: unknown;
    did?: unknown;
    pid?: unknown;
    iat?: unknown;
    exp?: unknown;
    n?: unknown;
  };
  try {
    payloadJson = base64UrlDecode(payloadB64).toString("utf8");
    payload = JSON.parse(payloadJson);
  } catch {
    return { ok: false, code: "DEVICE_TOKEN_MALFORMED" };
  }

  if (
    typeof payload.v !== "number" ||
    typeof payload.did !== "string" ||
    typeof payload.iat !== "number" ||
    typeof payload.exp !== "number" ||
    typeof payload.n !== "string" ||
    (payload.pid !== null && typeof payload.pid !== "string")
  ) {
    return { ok: false, code: "DEVICE_TOKEN_MALFORMED" };
  }

  if (payload.v !== DEVICE_TOKEN_VERSION) {
    return { ok: false, code: "DEVICE_TOKEN_VERSION_MISMATCH" };
  }

  const expected = signPayload(payloadB64, secret);
  let provided: Buffer;
  try {
    provided = base64UrlDecode(sigB64);
  } catch {
    return { ok: false, code: "DEVICE_TOKEN_MALFORMED" };
  }
  if (provided.length !== expected.length) {
    return { ok: false, code: "DEVICE_TOKEN_BAD_SIGNATURE" };
  }
  if (!timingSafeEqual(provided, expected)) {
    return { ok: false, code: "DEVICE_TOKEN_BAD_SIGNATURE" };
  }

  const nowSec = Math.floor((options.nowMs ?? Date.now()) / 1000);
  if (payload.exp <= nowSec) {
    return { ok: false, code: "DEVICE_TOKEN_EXPIRED" };
  }

  return {
    ok: true,
    claims: {
      version: payload.v,
      deviceInstallId: payload.did,
      participantId: payload.pid,
      issuedAt: payload.iat,
      expiresAt: payload.exp,
      nonce: payload.n,
    },
  };
}

export function extractBearerToken(
  headers: Record<string, string | undefined> | undefined,
): string | null {
  if (!headers) return null;
  const raw =
    headers["authorization"] ??
    headers["Authorization"] ??
    null;
  if (!raw || typeof raw !== "string") return null;
  const match = /^Bearer\s+(.+)$/i.exec(raw.trim());
  return match ? match[1].trim() : null;
}
