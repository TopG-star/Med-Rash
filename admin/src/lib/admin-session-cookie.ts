// Slice B1 phase 1 of docs/security-hardening-plan.md.
//
// HMAC-signed cookie that the Next.js middleware uses to enforce the agreed
// session timeout policy on every authenticated admin request:
//   - idle timeout     : 30 minutes since the last seen request
//   - absolute timeout :  8 hours since the original authentication
//
// Wire format (mirrors `_shared/device-token.ts`):
//   `${base64url(payloadJsonString)}.${base64url(signature)}`
//
// Payload (decoded JSON):
//   { v: 1, uid: string, authedAt: number, lastSeenAt: number, n: string }
//   - uid        = Supabase auth user id the cookie was issued for. If the
//                  cookie travels into a session belonging to a different
//                  Supabase user (e.g. signed out + signed back in as
//                  someone else without clearing cookies) the decision
//                  function treats it as "init" and rewrites the timestamps
//                  for the new identity.
//   - authedAt   = unix seconds the cookie was first issued for this uid.
//                  Drives the absolute timeout. NEVER updated by refresh.
//   - lastSeenAt = unix seconds of the most recent protected request.
//                  Updated on every successful middleware pass.
//   - n          = 8-byte hex nonce so two cookies minted in the same
//                  second differ (matches device-token).
//
// Signature: HMAC-SHA256(MEDRASH_ADMIN_SESSION_SECRET, payloadB64Url) via
// the Web Crypto API (`globalThis.crypto.subtle`) so the same module loads
// cleanly in both the Edge middleware runtime AND the Node route handlers
// that clear the cookie on signout. Do NOT switch to `node:crypto` here —
// it would break the middleware import on Edge.

export const ADMIN_SESSION_COOKIE_NAME = "medrash-admin-session";
export const ADMIN_SESSION_VERSION = 1 as const;
export const ADMIN_SESSION_IDLE_MS = 30 * 60 * 1000;
export const ADMIN_SESSION_ABSOLUTE_MS = 8 * 60 * 60 * 1000;

export type AdminSessionClaims = {
  version: number;
  userId: string;
  authedAt: number;
  lastSeenAt: number;
  nonce: string;
};

export type AdminSessionVerifyOk = { ok: true; claims: AdminSessionClaims };
export type AdminSessionVerifyErr = {
  ok: false;
  code:
    | "ADMIN_SESSION_MISSING"
    | "ADMIN_SESSION_MALFORMED"
    | "ADMIN_SESSION_BAD_SIGNATURE"
    | "ADMIN_SESSION_VERSION_MISMATCH"
    | "ADMIN_SESSION_SECRET_MISSING";
};
export type AdminSessionVerifyResult = AdminSessionVerifyOk | AdminSessionVerifyErr;

export type AdminSessionDecision =
  | { action: "init" }
  | { action: "ok"; refresh: true }
  | { action: "expire"; reason: "idle" | "absolute" };

function readSecret(): string | null {
  const raw = process.env.MEDRASH_ADMIN_SESSION_SECRET?.trim();
  if (!raw || raw.length < 32) return null;
  return raw;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary).replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
  const binary = atob(padded + pad);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
  return out;
}

function timingSafeEqualBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

async function signPayload(payloadB64: string, secret: string): Promise<Uint8Array> {
  const keyBytes = new TextEncoder().encode(secret);
  const key = await globalThis.crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await globalThis.crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payloadB64),
  );
  return new Uint8Array(sig);
}

function randomHexBytes(byteCount: number): string {
  const buf = new Uint8Array(byteCount);
  globalThis.crypto.getRandomValues(buf);
  let out = "";
  for (let i = 0; i < buf.length; i += 1) out += buf[i]!.toString(16).padStart(2, "0");
  return out;
}

export type SignInput = {
  userId: string;
  authedAt: number;
  lastSeenAt: number;
  nonce?: string;
};

export async function signAdminSessionCookie(input: SignInput): Promise<string> {
  const secret = readSecret();
  if (!secret) {
    throw new Error(
      "MEDRASH_ADMIN_SESSION_SECRET must be configured (>= 32 chars).",
    );
  }
  if (!input.userId || typeof input.userId !== "string") {
    throw new Error("signAdminSessionCookie: userId is required.");
  }
  const payload = {
    v: ADMIN_SESSION_VERSION,
    uid: input.userId,
    authedAt: input.authedAt,
    lastSeenAt: input.lastSeenAt,
    n: input.nonce ?? randomHexBytes(8),
  };
  const payloadB64 = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify(payload)),
  );
  const sigB64 = base64UrlEncode(await signPayload(payloadB64, secret));
  return `${payloadB64}.${sigB64}`;
}

export async function verifyAdminSessionCookie(
  raw: string | null | undefined,
): Promise<AdminSessionVerifyResult> {
  const secret = readSecret();
  if (!secret) return { ok: false, code: "ADMIN_SESSION_SECRET_MISSING" };
  if (!raw || typeof raw !== "string" || raw.length === 0) {
    return { ok: false, code: "ADMIN_SESSION_MISSING" };
  }
  const parts = raw.split(".");
  if (parts.length !== 2) return { ok: false, code: "ADMIN_SESSION_MALFORMED" };

  const [payloadB64, sigB64] = parts as [string, string];
  let payload: {
    v?: unknown;
    uid?: unknown;
    authedAt?: unknown;
    lastSeenAt?: unknown;
    n?: unknown;
  };
  try {
    const json = new TextDecoder().decode(base64UrlDecode(payloadB64));
    payload = JSON.parse(json);
  } catch {
    return { ok: false, code: "ADMIN_SESSION_MALFORMED" };
  }

  if (
    typeof payload.v !== "number" ||
    typeof payload.uid !== "string" ||
    typeof payload.authedAt !== "number" ||
    typeof payload.lastSeenAt !== "number" ||
    typeof payload.n !== "string"
  ) {
    return { ok: false, code: "ADMIN_SESSION_MALFORMED" };
  }
  if (payload.v !== ADMIN_SESSION_VERSION) {
    return { ok: false, code: "ADMIN_SESSION_VERSION_MISMATCH" };
  }

  const expected = await signPayload(payloadB64, secret);
  let provided: Uint8Array;
  try {
    provided = base64UrlDecode(sigB64);
  } catch {
    return { ok: false, code: "ADMIN_SESSION_MALFORMED" };
  }
  if (!timingSafeEqualBytes(provided, expected)) {
    return { ok: false, code: "ADMIN_SESSION_BAD_SIGNATURE" };
  }

  return {
    ok: true,
    claims: {
      version: payload.v,
      userId: payload.uid,
      authedAt: payload.authedAt,
      lastSeenAt: payload.lastSeenAt,
      nonce: payload.n,
    },
  };
}

export type DecideInput = {
  claims: AdminSessionClaims | null;
  currentUserId: string;
  nowMs: number;
  idleMaxMs?: number;
  absoluteMaxMs?: number;
};

/**
 * Pure decision function — no I/O. Middleware composes verify + decide +
 * sign. Exposed so the policy can be unit-tested without touching cookies
 * or crypto.
 *
 * Returns:
 *   - "init"   : no valid claims OR claims belong to a different uid.
 *                Middleware should mint a fresh cookie with both timestamps
 *                equal to now.
 *   - "expire" : claims exist for this uid but exceeded a timeout bound.
 *                Middleware should sign the Supabase session out and bounce
 *                to /login?reason=session_<reason>.
 *   - "ok"     : claims are healthy. Middleware should re-sign the cookie
 *                with lastSeenAt = now (refresh = true is invariant).
 */
export function decideAdminSession(input: DecideInput): AdminSessionDecision {
  const idleMaxMs = input.idleMaxMs ?? ADMIN_SESSION_IDLE_MS;
  const absoluteMaxMs = input.absoluteMaxMs ?? ADMIN_SESSION_ABSOLUTE_MS;
  if (!input.claims) return { action: "init" };
  if (input.claims.userId !== input.currentUserId) return { action: "init" };

  const authedAtMs = input.claims.authedAt * 1000;
  const lastSeenAtMs = input.claims.lastSeenAt * 1000;

  if (input.nowMs - authedAtMs > absoluteMaxMs) {
    return { action: "expire", reason: "absolute" };
  }
  if (input.nowMs - lastSeenAtMs > idleMaxMs) {
    return { action: "expire", reason: "idle" };
  }
  return { action: "ok", refresh: true };
}
