import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  DEVICE_TOKEN_TTL_SECONDS,
  extractBearerToken,
  mintDeviceToken,
  verifyDeviceToken,
} from "./device-token";

const ORIGINAL_ENV = { ...process.env };
const TEST_SECRET = "a".repeat(48);

beforeEach(() => {
  process.env.MEDRASH_DEVICE_TOKEN_SECRET = TEST_SECRET;
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("device-token", () => {
  it("round-trips: mint then verify returns the same claims", () => {
    const minted = mintDeviceToken({
      deviceInstallId: "device-uuid",
      participantId: "participant-uuid",
    });

    const verified = verifyDeviceToken(minted.token);
    expect(verified.ok).toBe(true);
    if (verified.ok) {
      expect(verified.claims.deviceInstallId).toBe("device-uuid");
      expect(verified.claims.participantId).toBe("participant-uuid");
      expect(verified.claims.expiresAt - verified.claims.issuedAt).toBe(
        DEVICE_TOKEN_TTL_SECONDS,
      );
    }
  });

  it("allows participantId to be null (bootstrap before profile binding)", () => {
    const minted = mintDeviceToken({ deviceInstallId: "device-uuid" });
    const verified = verifyDeviceToken(minted.token);
    expect(verified.ok).toBe(true);
    if (verified.ok) {
      expect(verified.claims.participantId).toBeNull();
    }
  });

  it("rejects a tampered payload", () => {
    const minted = mintDeviceToken({ deviceInstallId: "device-uuid" });
    const [_payload, sig] = minted.token.split(".");
    const tampered = `${Buffer.from(
      JSON.stringify({
        v: 1,
        did: "different-device",
        pid: null,
        iat: 0,
        exp: 9999999999,
        n: "deadbeef",
      }),
    )
      .toString("base64")
      .replace(/=+$/, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")}.${sig}`;

    const verified = verifyDeviceToken(tampered);
    expect(verified.ok).toBe(false);
    if (!verified.ok) {
      expect(verified.code).toBe("DEVICE_TOKEN_BAD_SIGNATURE");
    }
  });

  it("rejects a tampered signature", () => {
    const minted = mintDeviceToken({ deviceInstallId: "device-uuid" });
    const [payload] = minted.token.split(".");
    const verified = verifyDeviceToken(`${payload}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`);
    expect(verified.ok).toBe(false);
    if (!verified.ok) {
      expect(verified.code).toBe("DEVICE_TOKEN_BAD_SIGNATURE");
    }
  });

  it("rejects an expired token", () => {
    const past = Date.now() - 2 * DEVICE_TOKEN_TTL_SECONDS * 1000;
    const minted = mintDeviceToken({
      deviceInstallId: "device-uuid",
      nowMs: past,
    });
    const verified = verifyDeviceToken(minted.token);
    expect(verified.ok).toBe(false);
    if (!verified.ok) {
      expect(verified.code).toBe("DEVICE_TOKEN_EXPIRED");
    }
  });

  it("rejects a malformed token (wrong segment count)", () => {
    const verified = verifyDeviceToken("not-a-token");
    expect(verified.ok).toBe(false);
    if (!verified.ok) {
      expect(verified.code).toBe("DEVICE_TOKEN_MALFORMED");
    }
  });

  it("rejects a token signed with a different secret", () => {
    const minted = mintDeviceToken({ deviceInstallId: "device-uuid" });
    process.env.MEDRASH_DEVICE_TOKEN_SECRET = "b".repeat(48);
    const verified = verifyDeviceToken(minted.token);
    expect(verified.ok).toBe(false);
    if (!verified.ok) {
      expect(verified.code).toBe("DEVICE_TOKEN_BAD_SIGNATURE");
    }
  });

  it("throws if the secret env is missing or too short", () => {
    delete process.env.MEDRASH_DEVICE_TOKEN_SECRET;
    expect(() => mintDeviceToken({ deviceInstallId: "x" })).toThrow(
      /MEDRASH_DEVICE_TOKEN_SECRET/,
    );

    process.env.MEDRASH_DEVICE_TOKEN_SECRET = "too-short";
    expect(() => mintDeviceToken({ deviceInstallId: "x" })).toThrow(
      /MEDRASH_DEVICE_TOKEN_SECRET/,
    );

    const verified = verifyDeviceToken("anything.here");
    expect(verified.ok).toBe(false);
    if (!verified.ok) {
      expect(verified.code).toBe("DEVICE_TOKEN_SECRET_MISSING");
    }
  });

  it("returns a refresh window earlier than the expiry", () => {
    const minted = mintDeviceToken({ deviceInstallId: "device-uuid" });
    expect(minted.refreshAfter).toBeLessThan(minted.expiresAt);
    expect(minted.refreshAfter).toBeGreaterThan(minted.issuedAt);
  });
});

describe("extractBearerToken", () => {
  it("returns the token from a well-formed Authorization header", () => {
    expect(
      extractBearerToken({ authorization: "Bearer abc.def.ghi" }),
    ).toBe("abc.def.ghi");
    expect(
      extractBearerToken({ Authorization: "bearer abc.def" }),
    ).toBe("abc.def");
  });

  it("returns null when no header is present or shape is wrong", () => {
    expect(extractBearerToken(undefined)).toBeNull();
    expect(extractBearerToken({})).toBeNull();
    expect(extractBearerToken({ authorization: "Basic abc" })).toBeNull();
    expect(extractBearerToken({ authorization: "Bearer" })).toBeNull();
  });
});
