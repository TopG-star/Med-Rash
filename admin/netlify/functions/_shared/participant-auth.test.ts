import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { mintDeviceToken } from "./device-token";
import { requireParticipantAuth } from "./participant-auth";

const ORIGINAL_ENV = { ...process.env };
const TEST_SECRET = "a".repeat(48);
const GATE_KEY = "legacy-gate-key-for-test";

beforeEach(() => {
  process.env.MEDRASH_DEVICE_TOKEN_SECRET = TEST_SECRET;
  process.env.MEDRASH_GATE_API_KEY = GATE_KEY;
  delete process.env.MEDRASH_GATE_KEY_FALLBACK;
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("requireParticipantAuth", () => {
  it("accepts a valid device token via Authorization header", () => {
    const minted = mintDeviceToken({ deviceInstallId: "device-uuid" });
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: { authorization: `Bearer ${minted.token}` },
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.method).toBe("device-token");
      if (result.method === "device-token") {
        expect(result.claims.deviceInstallId).toBe("device-uuid");
      }
    }
  });

  it("rejects an invalid bearer without falling back to the gate key", () => {
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: {
        authorization: "Bearer obviously.broken",
        "x-medrash-gate-key": GATE_KEY,
      },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
    }
  });

  it("falls back to the legacy gate key when no bearer is present (default)", () => {
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: { "x-medrash-gate-key": GATE_KEY },
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.method).toBe("legacy-gate-key");
    }
  });

  it("rejects when no bearer is present and fallback is disabled", () => {
    process.env.MEDRASH_GATE_KEY_FALLBACK = "false";
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: { "x-medrash-gate-key": GATE_KEY },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
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

  it("rejects when the gate key is wrong and no bearer was sent", () => {
    const result = requireParticipantAuth({
      httpMethod: "POST",
      headers: { "x-medrash-gate-key": "wrong-key" },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.statusCode).toBe(401);
    }
  });
});
