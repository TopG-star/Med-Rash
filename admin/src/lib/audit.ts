import { createHash } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";

// Slice A5 (Pillar 6) — audit logging helpers.
//
// Two write-only helpers used from both Next.js server actions and Netlify
// functions. The caller supplies a service-role Supabase client because:
//   * Next.js path uses getAdminSupabaseClient() from supabase-server.ts
//   * Netlify path uses getSupabaseAdminClient()   from _shared/supabase.ts
// Both are already cached per-process; passing them in keeps this module
// pure and trivially mockable in tests.
//
// Invariant: BOTH helpers are fire-and-forget. They never throw, never
// reject — an audit insert failure is logged to console.error but MUST
// NOT block the calling request. Auditing is observability infrastructure;
// breaking the user flow because the audit channel is unavailable would
// be a self-inflicted DoS.
//
// PII discipline: email / ip / user-agent are hashed (SHA-256 of the
// trimmed-lowercased value) before being persisted. Same pattern as
// admin/src/lib/rate-limit.ts so cross-table joins on email_hash work
// for investigators without exposing the raw address.

export type AuthEventType =
  | "otp_request"
  | "otp_verify_success"
  | "otp_verify_fail"
  | "otp_rate_limited"
  | "allowlist_deny"
  | "recover_request"
  | "recover_verify_success"
  | "recover_verify_fail"
  | "recover_rate_limited"
  | "signout";

export type AuthEventInput = {
  eventType: AuthEventType;
  userId?: string | null;
  email?: string | null;
  ip?: string | null;
  userAgent?: string | null;
  result?: string | null;
  metadata?: Record<string, unknown>;
};

export type AdminActionInput = {
  actorUserId: string;
  actorRole: string;
  action: string;
  targetType: string;
  targetId?: string | null;
  payload?: unknown;
  metadata?: Record<string, unknown>;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnySupabaseClient = SupabaseClient<any, any, any, any, any>;

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function hashEmail(email: string): string {
  return sha256(email.trim().toLowerCase());
}

function hashOpaque(value: string): string {
  return sha256(value);
}

function hashPayload(payload: unknown): string | null {
  if (payload === undefined || payload === null) return null;
  try {
    return sha256(JSON.stringify(payload));
  } catch {
    // Unserialisable payload (e.g. circular reference). Skip the hash
    // rather than throw — caller's metadata.note can record why.
    return null;
  }
}

export async function logAuthEvent(
  client: AnySupabaseClient,
  input: AuthEventInput,
): Promise<void> {
  try {
    const row = {
      event_type: input.eventType,
      user_id: input.userId ?? null,
      email_hash: input.email ? hashEmail(input.email) : null,
      ip_hash: input.ip ? hashOpaque(input.ip) : null,
      user_agent_hash: input.userAgent ? hashOpaque(input.userAgent) : null,
      result: input.result ?? null,
      metadata: input.metadata ?? {},
    };
    const { error } = await client.from("auth_events").insert(row);
    if (error) {
      console.error("[audit] auth_events insert failed", {
        eventType: input.eventType,
        error: error.message,
      });
    }
  } catch (err) {
    console.error("[audit] logAuthEvent threw", err);
  }
}

export async function logAdminAction(
  client: AnySupabaseClient,
  input: AdminActionInput,
): Promise<void> {
  try {
    const row = {
      actor_user_id: input.actorUserId,
      actor_role: input.actorRole,
      action: input.action,
      target_type: input.targetType,
      target_id: input.targetId ?? null,
      payload_hash: hashPayload(input.payload),
      metadata: input.metadata ?? {},
    };
    const { error } = await client.from("admin_audit").insert(row);
    if (error) {
      console.error("[audit] admin_audit insert failed", {
        action: input.action,
        targetType: input.targetType,
        error: error.message,
      });
    }
  } catch (err) {
    console.error("[audit] logAdminAction threw", err);
  }
}
