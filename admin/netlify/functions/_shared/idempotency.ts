/**
 * P0.2 — server-side idempotency wrapper for admin write endpoints.
 *
 * Caller passes the request's `Idempotency-Key` header (when present) plus a
 * deterministic hash of the request body. The first call runs `exec` and
 * caches the (status, body) tuple in `app.idempotency_keys`. Subsequent
 * calls with the same (scope, key, request_hash) replay the cached 2xx
 * response without touching the underlying write path — exactly the
 * behaviour `session-create` and `quiz-bank-write` need so a Netlify retry
 * or accidental double-click never creates two sessions / two quizzes.
 *
 * If the same key arrives with a DIFFERENT request_hash we return 422
 * IDEMPOTENCY_KEY_REUSED so the caller knows they accidentally re-used a
 * key across two distinct intents.
 *
 * Non-2xx responses are NOT cached — re-running a failed handler is the
 * desired behaviour (the error may have been transient).
 *
 * No idempotency key supplied → exec runs once, nothing is cached.
 */

import { createHash } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";

import { jsonResponse } from "./http";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnySupabaseClient = SupabaseClient<any, any, any, any, any>;

export type IdempotencyScope =
  | "session_create"
  | "quiz_bank_write";

export type IdempotencyOptions = {
  scope: IdempotencyScope;
  /** Value of the `Idempotency-Key` request header. When null/empty the
   * wrapper just runs `exec` and returns its result. */
  key: string | null;
  /** Canonical hash of the request body so the same key cannot be reused
   * for two different intents. Caller is responsible for hashing. */
  requestHash: string;
  /** Optional metadata column on the cache row. */
  actorUserId?: string | null;
};

export type HandlerResult = {
  statusCode: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  body: Record<string, any>;
};

/** Compute the canonical SHA-256 of a request body. Stable across key
 * insertion order — sorts object keys recursively before stringifying. */
export function hashRequestBody(body: unknown): string {
  return createHash("sha256").update(canonicalize(body)).digest("hex");
}

function canonicalize(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return "[" + value.map(canonicalize).join(",") + "]";
  }
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return (
    "{" +
    keys.map((k) => JSON.stringify(k) + ":" + canonicalize(obj[k])).join(",") +
    "}"
  );
}

/** Read the `Idempotency-Key` header in a case-insensitive way. */
export function readIdempotencyKey(
  headers: Record<string, string | undefined> | undefined,
): string | null {
  if (!headers) return null;
  for (const [name, value] of Object.entries(headers)) {
    if (name.toLowerCase() === "idempotency-key" && typeof value === "string") {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }
  }
  return null;
}

type CachedRow = {
  scope: string;
  key: string;
  request_hash: string;
  response_status: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  response_body: Record<string, any>;
  expire_at: string;
};

export async function withIdempotency(
  client: AnySupabaseClient,
  options: IdempotencyOptions,
  exec: () => Promise<HandlerResult>,
): Promise<HandlerResult> {
  if (!options.key) {
    return exec();
  }

  // Look up an existing cached response.
  const { data: cached, error: lookupErr } = (await client
    .from("idempotency_keys")
    .select("scope, key, request_hash, response_status, response_body, expire_at")
    .eq("scope", options.scope)
    .eq("key", options.key)
    .gt("expire_at", new Date().toISOString())
    .maybeSingle()) as { data: CachedRow | null; error: { message: string } | null };

  if (lookupErr) {
    // Treat the cache as opt-in — if Postgres is unhappy, run the handler
    // and skip caching this round rather than 500-ing the user.
    console.error(
      "[idempotency] lookup failed; falling back to exec",
      lookupErr.message,
    );
    return exec();
  }

  if (cached) {
    if (cached.request_hash !== options.requestHash) {
      return {
        statusCode: 422,
        body: {
          ok: false,
          code: "IDEMPOTENCY_KEY_REUSED",
          message:
            "This Idempotency-Key was used for a different request. Pick a new key.",
        },
      };
    }
    return {
      statusCode: cached.response_status,
      body: cached.response_body ?? {},
    };
  }

  const result = await exec();

  // Only cache successful writes. Re-running a 4xx/5xx is the correct
  // behaviour — the error may have been transient (rate limit, db blip).
  if (result.statusCode >= 200 && result.statusCode < 300) {
    const { error: insertErr } = await client
      .from("idempotency_keys")
      .insert({
        scope: options.scope,
        key: options.key,
        actor_user_id: options.actorUserId ?? null,
        request_hash: options.requestHash,
        response_status: result.statusCode,
        response_body: result.body,
      });
    if (insertErr) {
      // Likely a race: a concurrent first-call beat us to the insert.
      // Re-read and replay theirs so both responses are identical.
      const { data: race } = (await client
        .from("idempotency_keys")
        .select("scope, key, request_hash, response_status, response_body, expire_at")
        .eq("scope", options.scope)
        .eq("key", options.key)
        .maybeSingle()) as { data: CachedRow | null; error: unknown };
      if (race && race.request_hash === options.requestHash) {
        return {
          statusCode: race.response_status,
          body: race.response_body ?? {},
        };
      }
      // Otherwise log and return the live result — the worst case is that
      // the next retry re-runs the handler, which the underlying write
      // path already tolerates (unique slug, unique join_code, etc.).
      console.error(
        "[idempotency] cache insert failed",
        insertErr.message ?? insertErr,
      );
    }
  }

  return result;
}

/** Convenience: render a [HandlerResult] as a Netlify v2 Response via the
 * shared jsonResponse helper. */
export function renderHandlerResult(result: HandlerResult) {
  return jsonResponse(result.statusCode, result.body);
}
