import { describe, it, expect, beforeEach, afterEach } from "vitest";

import { requireAdminUserSession } from "./admin-user-session";
import type { HandlerEvent } from "./http";

// ---------- Test fakes ----------

type AdminRow = { user_id: string; email: string; role: string; is_active: boolean } | null;

function makeAdminClient(row: AdminRow, error: { message: string } | null = null) {
  // Returns the bare-minimum shape of a Supabase chain used by the gate.
  return () =>
    ({
      from(_table: string) {
        return {
          select(_cols: string) {
            return {
              eq(_col: string, _val: string) {
                return {
                  async maybeSingle() {
                    return { data: row, error };
                  },
                };
              },
            };
          },
        };
      },
    }) as unknown as ReturnType<
      typeof import("./supabase").getSupabaseAdminClient
    >;
}

function makeAuthClient(user: { id: string; email: string } | null, error?: { message: string }) {
  return (_jwt: string) => ({
    auth: {
      async getUser(_token: string) {
        return error
          ? { data: { user: null }, error }
          : { data: { user }, error: null };
      },
    } as unknown as import("@supabase/supabase-js").SupabaseClient["auth"],
  });
}

function eventWith(headers: Record<string, string> = {}): HandlerEvent {
  return { httpMethod: "POST", headers, body: "{}" };
}

// ---------- Tests ----------

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  process.env.SUPABASE_URL = "https://example.supabase.co";
  process.env.SUPABASE_ANON_KEY = "anon-key";
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("requireAdminUserSession", () => {
  it("rejects a request with no Authorization header", async () => {
    const result = await requireAdminUserSession(eventWith(), {
      authClientFor: makeAuthClient(null),
      adminClient: makeAdminClient(null),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
    }
  });

  it("rejects a non-bearer Authorization header", async () => {
    const result = await requireAdminUserSession(
      eventWith({ authorization: "Basic abc" }),
      {
        authClientFor: makeAuthClient(null),
        adminClient: makeAdminClient(null),
      },
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(401);
  });

  it("rejects a bearer token Supabase cannot decode", async () => {
    const result = await requireAdminUserSession(
      eventWith({ authorization: "Bearer bad-token" }),
      {
        authClientFor: makeAuthClient(null, { message: "bad jwt" }),
        adminClient: makeAdminClient(null),
      },
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(401);
  });

  it("rejects a verified user not on the allowlist", async () => {
    const result = await requireAdminUserSession(
      eventWith({ authorization: "Bearer good" }),
      {
        authClientFor: makeAuthClient({ id: "user-1", email: "x@y.com" }),
        adminClient: makeAdminClient(null),
      },
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(403);
  });

  it("rejects an allowlisted user whose row is inactive", async () => {
    const result = await requireAdminUserSession(
      eventWith({ authorization: "Bearer good" }),
      {
        authClientFor: makeAuthClient({ id: "user-1", email: "x@y.com" }),
        adminClient: makeAdminClient({
          user_id: "user-1",
          email: "x@y.com",
          role: "host",
          is_active: false,
        }),
      },
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(403);
  });

  it("accepts an active allowlisted host", async () => {
    const result = await requireAdminUserSession(
      eventWith({ authorization: "Bearer good" }),
      {
        authClientFor: makeAuthClient({ id: "user-1", email: "x@y.com" }),
        adminClient: makeAdminClient({
          user_id: "user-1",
          email: "x@y.com",
          role: "host",
          is_active: true,
        }),
      },
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.auth.userId).toBe("user-1");
      expect(result.auth.role).toBe("host");
      expect(result.auth.via).toBe("bearer");
    }
  });

  it("promotes an owner role correctly", async () => {
    const result = await requireAdminUserSession(
      eventWith({ authorization: "Bearer good" }),
      {
        authClientFor: makeAuthClient({ id: "user-2", email: "boss@y.com" }),
        adminClient: makeAdminClient({
          user_id: "user-2",
          email: "boss@y.com",
          role: "owner",
          is_active: true,
        }),
      },
    );
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.auth.role).toBe("owner");
  });

  it("accepts the internal-bypass header when the env secret matches", async () => {
    process.env.MEDRASH_INTERNAL_BYPASS = "shhh";
    const result = await requireAdminUserSession(
      eventWith({ "x-medrash-internal-bypass": "shhh" }),
      {
        authClientFor: makeAuthClient(null),
        adminClient: makeAdminClient(null),
      },
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.auth.via).toBe("internal-bypass");
      expect(result.auth.role).toBe("owner");
    }
  });

  it("does not accept the internal-bypass header when env is unset", async () => {
    delete process.env.MEDRASH_INTERNAL_BYPASS;
    const result = await requireAdminUserSession(
      eventWith({ "x-medrash-internal-bypass": "anything" }),
      {
        authClientFor: makeAuthClient(null),
        adminClient: makeAdminClient(null),
      },
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.statusCode).toBe(401);
  });
});
