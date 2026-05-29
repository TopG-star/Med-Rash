import { beforeEach, describe, expect, it } from "vitest";

import {
  ADMIN_SESSION_ABSOLUTE_MS,
  ADMIN_SESSION_IDLE_MS,
  decideAdminSession,
  signAdminSessionCookie,
  verifyAdminSessionCookie,
  type AdminSessionClaims,
} from "./admin-session-cookie";

const TEST_SECRET = "a".repeat(48);

beforeEach(() => {
  process.env.MEDRASH_ADMIN_SESSION_SECRET = TEST_SECRET;
});

describe("admin-session-cookie crypto", () => {
  it("signs then verifies a happy-path payload", async () => {
    const cookie = await signAdminSessionCookie({
      userId: "user-1",
      authedAt: 1_000_000,
      lastSeenAt: 1_000_000,
      nonce: "deadbeefdeadbeef",
    });
    const result = await verifyAdminSessionCookie(cookie);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.claims.userId).toBe("user-1");
      expect(result.claims.authedAt).toBe(1_000_000);
      expect(result.claims.lastSeenAt).toBe(1_000_000);
      expect(result.claims.nonce).toBe("deadbeefdeadbeef");
      expect(result.claims.version).toBe(1);
    }
  });

  it("rejects ADMIN_SESSION_MISSING when raw is null or empty", async () => {
    expect((await verifyAdminSessionCookie(null)).ok).toBe(false);
    expect((await verifyAdminSessionCookie("")).ok).toBe(false);
    const r = await verifyAdminSessionCookie(undefined);
    if (!r.ok) expect(r.code).toBe("ADMIN_SESSION_MISSING");
  });

  it("rejects ADMIN_SESSION_MALFORMED on garbage input", async () => {
    const r = await verifyAdminSessionCookie("not-a-token-shape");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("ADMIN_SESSION_MALFORMED");
  });

  it("rejects ADMIN_SESSION_BAD_SIGNATURE when tampered", async () => {
    const cookie = await signAdminSessionCookie({
      userId: "user-1",
      authedAt: 1_000_000,
      lastSeenAt: 1_000_000,
    });
    const [payload] = cookie.split(".");
    const tampered = `${payload}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`;
    const r = await verifyAdminSessionCookie(tampered);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("ADMIN_SESSION_BAD_SIGNATURE");
  });

  it("rejects ADMIN_SESSION_SECRET_MISSING when env var is unset", async () => {
    delete process.env.MEDRASH_ADMIN_SESSION_SECRET;
    const r = await verifyAdminSessionCookie("anything");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("ADMIN_SESSION_SECRET_MISSING");
  });

  it("rejects ADMIN_SESSION_SECRET_MISSING when secret is too short", async () => {
    process.env.MEDRASH_ADMIN_SESSION_SECRET = "short";
    const r = await verifyAdminSessionCookie("anything");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("ADMIN_SESSION_SECRET_MISSING");
  });

  it("sign throws when secret missing", async () => {
    delete process.env.MEDRASH_ADMIN_SESSION_SECRET;
    await expect(
      signAdminSessionCookie({ userId: "u", authedAt: 1, lastSeenAt: 1 }),
    ).rejects.toThrow(/MEDRASH_ADMIN_SESSION_SECRET/);
  });
});

describe("decideAdminSession", () => {
  const baseClaims: AdminSessionClaims = {
    version: 1,
    userId: "user-1",
    authedAt: 1_000_000,
    lastSeenAt: 1_000_000,
    nonce: "n",
  };

  it("returns init when claims are null", () => {
    expect(
      decideAdminSession({
        claims: null,
        currentUserId: "user-1",
        nowMs: 1_000_000_000,
      }),
    ).toEqual({ action: "init" });
  });

  it("returns init when claims belong to a different user", () => {
    expect(
      decideAdminSession({
        claims: baseClaims,
        currentUserId: "user-2",
        nowMs: baseClaims.authedAt * 1000 + 1000,
      }),
    ).toEqual({ action: "init" });
  });

  it("returns ok when within both idle and absolute bounds", () => {
    const r = decideAdminSession({
      claims: { ...baseClaims, lastSeenAt: 1_000_500 },
      currentUserId: "user-1",
      nowMs: 1_000_500_000 + 1000, // 1s past lastSeen
    });
    expect(r).toEqual({ action: "ok", refresh: true });
  });

  it("expires on absolute timeout (8h)", () => {
    const r = decideAdminSession({
      claims: baseClaims,
      currentUserId: "user-1",
      nowMs: baseClaims.authedAt * 1000 + ADMIN_SESSION_ABSOLUTE_MS + 1,
    });
    expect(r).toEqual({ action: "expire", reason: "absolute" });
  });

  it("expires on idle timeout (30m) even when within absolute bound", () => {
    const r = decideAdminSession({
      claims: { ...baseClaims, lastSeenAt: 1_000_000 },
      currentUserId: "user-1",
      nowMs: 1_000_000 * 1000 + ADMIN_SESSION_IDLE_MS + 1,
    });
    expect(r).toEqual({ action: "expire", reason: "idle" });
  });

  it("prefers absolute over idle when both are exceeded", () => {
    // both bounds exceeded - absolute is checked first per the policy doc
    const r = decideAdminSession({
      claims: { ...baseClaims, lastSeenAt: 1_000_000 },
      currentUserId: "user-1",
      nowMs:
        baseClaims.authedAt * 1000 + ADMIN_SESSION_ABSOLUTE_MS + 60_000,
    });
    expect(r).toEqual({ action: "expire", reason: "absolute" });
  });

  it("respects custom bounds (used for tests / future tunables)", () => {
    const r = decideAdminSession({
      claims: baseClaims,
      currentUserId: "user-1",
      nowMs: baseClaims.authedAt * 1000 + 10_000,
      idleMaxMs: 5_000,
      absoluteMaxMs: 60_000,
    });
    expect(r).toEqual({ action: "expire", reason: "idle" });
  });
});
