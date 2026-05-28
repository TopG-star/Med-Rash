import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { mintDeviceToken } from "./device-token";
import { requireParticipantAuth } from "./participant-auth";

const ORIGINAL_ENV = { ...process.env };
const TEST_SECRET = "a".repeat(48);
const STALE_GATE_KEY = "stale-gate-key-header-value";

beforeEach(() => {
  process.env.MEDRASH_DEVICE_TOKEN_SECRET = TEST_SECRET;
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("requireParticipantAuth (Phase 3c — bearer-only, gate-key removed)", () => {
  it("accepts a valid device token via Authorization header", () => {
    const minted = mintDeviceToken({ deviceInstallId: "device-uuid" });
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: { authorization: `Bearer ${minted.token}` },
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.method).toBe("device-token");
      expect(result.claims.deviceInstallId).toBe("device-uuid");
    }
  });

  it("rejects an invalid bearer with 401 (no fallback)", () => {
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: {
        authorization: "Bearer obviously.broken",
        "x-medrash-gate-key": STALE_GATE_KEY,
      },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
    }
  });

  it("rejects with 401 when only the (removed) legacy gate-key header is supplied", () => {
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: { "x-medrash-gate-key": STALE_GATE_KEY },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
      const body = JSON.parse(result.response.body as string) as {
        code: string;
      };
      expect(body.code).toBe("UNAUTHORIZED");
    }
  });

  it("rejects when no auth at all is supplied", () => {
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: {},
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
    }
  });

  it("ignores MEDRASH_GATE_KEY_FALLBACK env var entirely (kill-switch is gone)", () => {
    process.env.MEDRASH_GATE_KEY_FALLBACK = "true";
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: { "x-medrash-gate-key": STALE_GATE_KEY },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
    }
  });
});
