import { createHash } from "node:crypto";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { logAdminAction, logAuthEvent } from "./audit";

// Fake Supabase service-role client. Captures inserted rows so tests can
// assert hashing + fire-and-forget invariants without touching Postgres.
type Insert = { table: string; row: Record<string, unknown> };

function buildFakeClient(opts: { failOn?: string } = {}) {
  const inserts: Insert[] = [];
  const client = {
    inserts,
    from(table: string) {
      return {
        insert(row: Record<string, unknown>) {
          inserts.push({ table, row });
          if (opts.failOn === table) {
            return Promise.resolve({
              error: { message: `simulated ${table} failure` },
            });
          }
          return Promise.resolve({ error: null });
        },
      };
    },
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return client as any;
}

function sha256(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

describe("logAuthEvent", () => {
  let errSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  });
  afterEach(() => {
    errSpy.mockRestore();
  });

  it("hashes email (lowercased + trimmed), ip, and user-agent before insert", async () => {
    const client = buildFakeClient();
    await logAuthEvent(client, {
      eventType: "otp_request",
      email: "  Owner@MedRash.io  ",
      ip: "203.0.113.7",
      userAgent: "Mozilla/5.0",
      result: "code_sent",
    });

    expect(client.inserts).toHaveLength(1);
    const row = client.inserts[0].row;
    expect(client.inserts[0].table).toBe("auth_events");
    expect(row.event_type).toBe("otp_request");
    expect(row.email_hash).toBe(sha256("owner@medrash.io"));
    expect(row.ip_hash).toBe(sha256("203.0.113.7"));
    expect(row.user_agent_hash).toBe(sha256("Mozilla/5.0"));
    expect(row.result).toBe("code_sent");
    expect(row.metadata).toEqual({});
    // Raw PII must never appear in the insert payload.
    expect(JSON.stringify(row)).not.toContain("owner@medrash.io");
    expect(JSON.stringify(row)).not.toContain("203.0.113.7");
    expect(JSON.stringify(row)).not.toContain("Mozilla/5.0");
  });

  it("leaves email_hash / ip_hash / user_agent_hash null when inputs are absent", async () => {
    const client = buildFakeClient();
    await logAuthEvent(client, { eventType: "signout", userId: "user-123" });

    const row = client.inserts[0].row;
    expect(row.user_id).toBe("user-123");
    expect(row.email_hash).toBeNull();
    expect(row.ip_hash).toBeNull();
    expect(row.user_agent_hash).toBeNull();
  });

  it("never throws when the insert fails (fire-and-forget invariant)", async () => {
    const client = buildFakeClient({ failOn: "auth_events" });
    await expect(
      logAuthEvent(client, { eventType: "otp_verify_fail", email: "a@b.io" }),
    ).resolves.toBeUndefined();
    expect(errSpy).toHaveBeenCalledWith(
      "[audit] auth_events insert failed",
      expect.objectContaining({ eventType: "otp_verify_fail" }),
    );
  });

  it("never throws when the client itself throws (fire-and-forget invariant)", async () => {
    const brokenClient = {
      from() {
        throw new Error("client exploded");
      },
    };
    await expect(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      logAuthEvent(brokenClient as any, { eventType: "signout" }),
    ).resolves.toBeUndefined();
    expect(errSpy).toHaveBeenCalledWith(
      "[audit] logAuthEvent threw",
      expect.any(Error),
    );
  });
});

describe("logAdminAction", () => {
  let errSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  });
  afterEach(() => {
    errSpy.mockRestore();
  });

  it("inserts actor + action + target with a stable SHA-256 payload_hash", async () => {
    const client = buildFakeClient();
    const payload = { quizId: "q1", title: "Renal Phys" };
    await logAdminAction(client, {
      actorUserId: "user-1",
      actorRole: "owner",
      action: "create_quiz",
      targetType: "quiz",
      targetId: "q1",
      payload,
    });

    const row = client.inserts[0].row;
    expect(client.inserts[0].table).toBe("admin_audit");
    expect(row.actor_user_id).toBe("user-1");
    expect(row.actor_role).toBe("owner");
    expect(row.action).toBe("create_quiz");
    expect(row.target_type).toBe("quiz");
    expect(row.target_id).toBe("q1");
    expect(row.payload_hash).toBe(sha256(JSON.stringify(payload)));
    expect(row.metadata).toEqual({});
  });

  it("leaves payload_hash null when no payload is provided", async () => {
    const client = buildFakeClient();
    await logAdminAction(client, {
      actorUserId: "user-1",
      actorRole: "host",
      action: "session_create",
      targetType: "session",
      targetId: "sess-1",
    });
    expect(client.inserts[0].row.payload_hash).toBeNull();
  });

  it("never throws when the insert fails (fire-and-forget invariant)", async () => {
    const client = buildFakeClient({ failOn: "admin_audit" });
    await expect(
      logAdminAction(client, {
        actorUserId: "u",
        actorRole: "owner",
        action: "x",
        targetType: "y",
      }),
    ).resolves.toBeUndefined();
    expect(errSpy).toHaveBeenCalledWith(
      "[audit] admin_audit insert failed",
      expect.objectContaining({ action: "x", targetType: "y" }),
    );
  });
});
