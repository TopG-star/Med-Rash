import { describe, expect, it } from "vitest";

import {
  hashRequestBody,
  readIdempotencyKey,
  withIdempotency,
} from "./idempotency";

// In-memory fake of the `app.idempotency_keys` table — exercises the same
// surface the helper uses (.from().select/.insert/.eq/.gt/.maybeSingle).
type CachedRow = {
  scope: string;
  key: string;
  request_hash: string;
  response_status: number;
  response_body: Record<string, unknown>;
  expire_at: string;
};

function fakeClient() {
  const rows: CachedRow[] = [];

  function buildSelectChain(filters: Record<string, string> = {}) {
    return {
      eq(column: string, value: string) {
        return buildSelectChain({ ...filters, [column]: value });
      },
      gt(_column: string, _value: string) {
        return buildSelectChain(filters);
      },
      async maybeSingle() {
        const match = rows.find((r) =>
          Object.entries(filters).every(
            ([k, v]) => (r as unknown as Record<string, string>)[k] === v,
          ),
        );
        return { data: match ?? null, error: null };
      },
    };
  }

  return {
    rows,
    from(table: string) {
      if (table !== "idempotency_keys") {
        throw new Error(`Unexpected table ${table}`);
      }
      return {
        select(_cols: string) {
          return buildSelectChain();
        },
        async insert(row: Omit<CachedRow, "expire_at"> & { actor_user_id?: string | null }) {
          const exists = rows.find(
            (r) => r.scope === row.scope && r.key === row.key,
          );
          if (exists) {
            return { error: { message: "duplicate key" } } as const;
          }
          rows.push({
            scope: row.scope,
            key: row.key,
            request_hash: row.request_hash,
            response_status: row.response_status,
            response_body: row.response_body,
            expire_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          });
          return { error: null } as const;
        },
      };
    },
  };
}

describe("readIdempotencyKey", () => {
  it("reads the header case-insensitively", () => {
    expect(readIdempotencyKey({ "Idempotency-Key": "abc" })).toBe("abc");
    expect(readIdempotencyKey({ "idempotency-key": "xyz" })).toBe("xyz");
  });

  it("returns null when missing or empty", () => {
    expect(readIdempotencyKey(undefined)).toBeNull();
    expect(readIdempotencyKey({})).toBeNull();
    expect(readIdempotencyKey({ "idempotency-key": "  " })).toBeNull();
  });
});

describe("hashRequestBody", () => {
  it("is stable across key insertion order", () => {
    const a = hashRequestBody({ b: 2, a: 1 });
    const b = hashRequestBody({ a: 1, b: 2 });
    expect(a).toBe(b);
  });

  it("changes when payload changes", () => {
    expect(hashRequestBody({ a: 1 })).not.toBe(hashRequestBody({ a: 2 }));
  });
});

describe("withIdempotency", () => {
  it("runs exec when no key is supplied", async () => {
    const client = fakeClient();
    let calls = 0;
    const result = await withIdempotency(
      client as never,
      {
        scope: "session_create",
        key: null,
        requestHash: "h",
      },
      async () => {
        calls += 1;
        return { statusCode: 201, body: { ok: true, calls } };
      },
    );
    expect(calls).toBe(1);
    expect(result.statusCode).toBe(201);
    expect(client.rows).toHaveLength(0);
  });

  it("caches a 2xx response and replays it on the second call", async () => {
    const client = fakeClient();
    let calls = 0;
    const exec = async () => {
      calls += 1;
      return { statusCode: 201, body: { ok: true, id: "s_1" } };
    };

    const first = await withIdempotency(
      client as never,
      { scope: "session_create", key: "k1", requestHash: "hash-A" },
      exec,
    );
    const second = await withIdempotency(
      client as never,
      { scope: "session_create", key: "k1", requestHash: "hash-A" },
      exec,
    );

    expect(calls).toBe(1);
    expect(first).toEqual(second);
    expect(client.rows).toHaveLength(1);
  });

  it("returns 422 when the same key arrives with a different request hash", async () => {
    const client = fakeClient();
    await withIdempotency(
      client as never,
      { scope: "session_create", key: "k2", requestHash: "hash-A" },
      async () => ({ statusCode: 201, body: { ok: true } }),
    );

    const conflict = await withIdempotency(
      client as never,
      { scope: "session_create", key: "k2", requestHash: "hash-B" },
      async () => {
        throw new Error("exec must not run on hash conflict");
      },
    );

    expect(conflict.statusCode).toBe(422);
    expect(conflict.body.code).toBe("IDEMPOTENCY_KEY_REUSED");
  });

  it("does not cache non-2xx responses", async () => {
    const client = fakeClient();
    let calls = 0;
    const exec = async () => {
      calls += 1;
      return { statusCode: 500, body: { ok: false, code: "BOOM" } };
    };

    await withIdempotency(
      client as never,
      { scope: "session_create", key: "k3", requestHash: "h" },
      exec,
    );
    await withIdempotency(
      client as never,
      { scope: "session_create", key: "k3", requestHash: "h" },
      exec,
    );

    expect(calls).toBe(2);
    expect(client.rows).toHaveLength(0);
  });
});
