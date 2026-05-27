import { createHash } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";

// Slice A1 — Postgres-backed OTP + per-identifier rate limiter.
//
// Replaces the in-memory map that previously lived in
// admin/src/app/login/actions.ts. Both Next.js server actions and Netlify
// functions can use this module because it accepts the Supabase client as
// an argument (the caller is responsible for supplying a service-role
// client bound to the `app` schema).
//
// All scopes are namespaced; identifiers are SHA-256 hashed before they
// hit the database so we never persist raw emails or IPs in
// app.auth_rate_limit (privacy discipline from plan §3, slice A5).

export type RateLimitScope =
  | "auth_otp_request"
  | "auth_otp_verify"
  | "recover_otp_request"
  | "recover_otp_verify";

export type RateLimitConfig = {
  scope: RateLimitScope;
  identifier: string;
  limit: number;
  windowSeconds: number;
  lockoutSeconds: number;
};

export type RateLimitDecision = {
  allowed: boolean;
  attemptsRemaining: number;
  retryAfterSeconds: number;
  lockedUntil: Date | null;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnySupabaseClient = SupabaseClient<any, any, any, any, any>;

function buildKey(scope: RateLimitScope, identifier: string): string {
  const normalized = identifier.trim().toLowerCase();
  const hash = createHash("sha256").update(normalized).digest("hex");
  return `${scope}:${hash}`;
}

type EnforceRow = {
  allowed: boolean;
  attempts_remaining: number;
  retry_after_seconds: number;
  locked_until: string | null;
};

export async function enforceRateLimit(
  client: AnySupabaseClient,
  config: RateLimitConfig,
): Promise<RateLimitDecision> {
  if (!config.identifier || config.identifier.trim().length === 0) {
    throw new Error("enforceRateLimit: identifier is required.");
  }

  const key = buildKey(config.scope, config.identifier);
  const { data, error } = await client.rpc("enforce_rate_limit", {
    p_key: key,
    p_limit: config.limit,
    p_window_seconds: config.windowSeconds,
    p_lockout_seconds: config.lockoutSeconds,
  });

  if (error) {
    throw new Error(`enforceRateLimit failed: ${error.message}`);
  }

  const row = Array.isArray(data) ? (data[0] as EnforceRow | undefined) : (data as EnforceRow | null);
  if (!row) {
    throw new Error("enforceRateLimit returned no row.");
  }

  return {
    allowed: row.allowed,
    attemptsRemaining: row.attempts_remaining ?? 0,
    retryAfterSeconds: row.retry_after_seconds ?? 0,
    lockedUntil: row.locked_until ? new Date(row.locked_until) : null,
  };
}

export async function resetRateLimit(
  client: AnySupabaseClient,
  scope: RateLimitScope,
  identifier: string,
): Promise<void> {
  if (!identifier || identifier.trim().length === 0) {
    return;
  }
  const key = buildKey(scope, identifier);
  const { error } = await client.rpc("reset_rate_limit", { p_key: key });
  if (error) {
    throw new Error(`resetRateLimit failed: ${error.message}`);
  }
}

// Centralised defaults so every entry point uses the same numbers. Tuned
// in plan §3 slice A1:
//   - request scopes (sending a code) are tighter than verify scopes
//     because they trigger an email send (cost + abuse signal).
//   - 15-minute window matches Supabase Auth's own OTP TTL — once the
//     code expires, the wrong-OTP counter is no longer useful anyway.
//   - lockout equals the window so a tripped limit resolves cleanly when
//     the window rolls over.
export const RATE_LIMITS: Record<RateLimitScope, Omit<RateLimitConfig, "scope" | "identifier">> = {
  auth_otp_request: { limit: 5, windowSeconds: 15 * 60, lockoutSeconds: 15 * 60 },
  auth_otp_verify: { limit: 5, windowSeconds: 15 * 60, lockoutSeconds: 15 * 60 },
  recover_otp_request: { limit: 3, windowSeconds: 15 * 60, lockoutSeconds: 15 * 60 },
  recover_otp_verify: { limit: 5, windowSeconds: 15 * 60, lockoutSeconds: 15 * 60 },
};

export function rateLimitConfig(
  scope: RateLimitScope,
  identifier: string,
): RateLimitConfig {
  return { scope, identifier, ...RATE_LIMITS[scope] };
}

export function formatLockoutMessage(decision: RateLimitDecision): string {
  if (decision.allowed) return "";
  const minutes = Math.max(1, Math.ceil(decision.retryAfterSeconds / 60));
  return `Too many attempts. Try again in ${minutes} minute${minutes === 1 ? "" : "s"}.`;
}
