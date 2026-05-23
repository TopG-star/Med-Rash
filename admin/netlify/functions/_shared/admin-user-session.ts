import "server-only";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { getSupabaseAdminClient } from "./supabase";
import {
  jsonResponse,
  type HandlerEvent,
  type HandlerResponse,
} from "./http";

type AdminRole = "admin" | "superadmin";

export type AdminAuth = {
  userId: string;
  email: string;
  role: AdminRole;
  via: "bearer" | "internal-bypass";
};

export type RequireAdminUserSessionDeps = {
  /**
   * Build a Supabase auth client bound to the user's bearer JWT. Defaulted
   * to the real implementation; overridable for tests.
   */
  authClientFor?: (jwt: string) => Pick<SupabaseClient, "auth">;
  /** Service-role client for the admin_users allowlist lookup. */
  adminClient?: () => ReturnType<typeof getSupabaseAdminClient>;
};

function readHeader(
  event: HandlerEvent,
  name: string,
): string | undefined {
  const headers = event.headers ?? {};
  const lower = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === lower && typeof value === "string") {
      return value;
    }
  }
  return undefined;
}

function defaultAuthClientFor(jwt: string): Pick<SupabaseClient, "auth"> {
  const url = process.env.SUPABASE_URL?.trim();
  const anon = process.env.SUPABASE_ANON_KEY?.trim();
  if (!url) throw new Error("SUPABASE_URL is not configured.");
  if (!anon) throw new Error("SUPABASE_ANON_KEY is not configured.");

  return createClient(url, anon, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
}

/**
 * Gate for admin WRITE operations served by Netlify Functions.
 *
 * Two acceptable proofs:
 *   1. `Authorization: Bearer <supabase-jwt>` belonging to an active row
 *      in app.admin_users.
 *   2. `x-medrash-internal-bypass: <MEDRASH_INTERNAL_BYPASS>` for server-to-
 *      server / scheduled calls that don't carry a user session. The bypass
 *      is treated as a synthetic "system" superadmin so it cannot be used
 *      to impersonate a real human.
 *
 * The legacy `x-medrash-admin-write-key` shared secret is ALSO honored as a
 * defense-in-depth pre-check by `requireLegacyWriteKey` so an attacker who
 * obtains only one of the two cannot escalate.
 *
 * Returns `{ ok: true, auth }` or `{ ok: false, response }`.
 */
export async function requireAdminUserSession(
  event: HandlerEvent,
  deps: RequireAdminUserSessionDeps = {},
): Promise<
  { ok: true; auth: AdminAuth } | { ok: false; response: HandlerResponse }
> {
  // Path 2 — internal bypass.
  const bypassExpected = process.env.MEDRASH_INTERNAL_BYPASS?.trim();
  const bypassIncoming = readHeader(event, "x-medrash-internal-bypass")?.trim();
  if (bypassExpected && bypassIncoming && bypassIncoming === bypassExpected) {
    return {
      ok: true,
      auth: {
        userId: "00000000-0000-0000-0000-000000000000",
        email: "internal@medrash.system",
        role: "superadmin",
        via: "internal-bypass",
      },
    };
  }

  // Path 1 — Bearer JWT.
  const authHeader = readHeader(event, "authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: "UNAUTHORIZED_ADMIN_WRITE",
        message: "Missing bearer token.",
      }),
    };
  }
  const jwt = authHeader.slice("bearer ".length).trim();
  if (!jwt) {
    return {
      ok: false,
      response: jsonResponse(401, {
        ok: false,
        code: "UNAUTHORIZED_ADMIN_WRITE",
        message: "Empty bearer token.",
      }),
    };
  }

  let userId: string;
  let email: string;
  try {
    const authClient = (deps.authClientFor ?? defaultAuthClientFor)(jwt);
    const { data, error } = await authClient.auth.getUser(jwt);
    if (error || !data.user) {
      return {
        ok: false,
        response: jsonResponse(401, {
          ok: false,
          code: "UNAUTHORIZED_ADMIN_WRITE",
          message: "Bearer token is not a valid Supabase session.",
        }),
      };
    }
    userId = data.user.id;
    email = data.user.email ?? "";
    if (!email) {
      return {
        ok: false,
        response: jsonResponse(401, {
          ok: false,
          code: "UNAUTHORIZED_ADMIN_WRITE",
          message: "Bearer token is missing an email claim.",
        }),
      };
    }
  } catch (err) {
    console.error("[admin-user-session] getUser failed", err);
    return {
      ok: false,
      response: jsonResponse(500, {
        ok: false,
        code: "ADMIN_AUTH_INTERNAL_ERROR",
        message: "Could not verify bearer token.",
      }),
    };
  }

  // Allowlist lookup.
  const supabase = (deps.adminClient ?? getSupabaseAdminClient)();
  const { data: row, error: lookupError } = await supabase
    .from("admin_users")
    .select("user_id, email, role, is_active")
    .eq("user_id", userId)
    .maybeSingle();

  if (lookupError) {
    console.error("[admin-user-session] allowlist lookup failed", lookupError);
    return {
      ok: false,
      response: jsonResponse(500, {
        ok: false,
        code: "ADMIN_AUTH_INTERNAL_ERROR",
        message: "Allowlist lookup failed.",
      }),
    };
  }
  if (!row || row.is_active !== true) {
    return {
      ok: false,
      response: jsonResponse(403, {
        ok: false,
        code: "FORBIDDEN_ADMIN_WRITE",
        message: "Account is not on the admin allowlist.",
      }),
    };
  }

  const role: AdminRole = row.role === "superadmin" ? "superadmin" : "admin";
  return {
    ok: true,
    auth: { userId, email, role, via: "bearer" },
  };
}

/**
 * Defense-in-depth pre-check. Kept as a thin layer so callers can opt out
 * cleanly by setting MEDRASH_ADMIN_WRITE_KEY to empty.
 */
export function requireLegacyWriteKey(
  event: HandlerEvent,
): HandlerResponse | null {
  const expected = process.env.MEDRASH_ADMIN_WRITE_KEY?.trim();
  if (!expected) return null; // disabled
  const incoming = readHeader(event, "x-medrash-admin-write-key")?.trim() ?? "";
  if (incoming !== expected) {
    return jsonResponse(401, {
      ok: false,
      code: "UNAUTHORIZED_ADMIN_WRITE",
      message: "Missing or invalid x-medrash-admin-write-key.",
    });
  }
  return null;
}
