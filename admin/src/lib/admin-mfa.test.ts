import { describe, expect, it } from "vitest";

import {
  RECOVERY_CODE_COUNT,
  generateRecoveryCodes,
  hashRecoveryCode,
  matchRecoveryCode,
  normalizeRecoveryCode,
} from "./admin-mfa";

describe("generateRecoveryCodes", () => {
  it("returns the default count of unique codes", () => {
    const codes = generateRecoveryCodes();
    expect(codes).toHaveLength(RECOVERY_CODE_COUNT);
    expect(new Set(codes).size).toBe(RECOVERY_CODE_COUNT);
  });

  it("formats each code as XXXX-XXXX-XXXX from the no-ambiguous alphabet", () => {
    const codes = generateRecoveryCodes(8);
    for (const code of codes) {
      expect(code).toMatch(/^[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$/);
    }
  });

  it("respects an explicit count", () => {
    expect(generateRecoveryCodes(1)).toHaveLength(1);
    expect(generateRecoveryCodes(16)).toHaveLength(16);
  });

  it("rejects out-of-range counts", () => {
    expect(() => generateRecoveryCodes(0)).toThrow();
    expect(() => generateRecoveryCodes(-1)).toThrow();
    expect(() => generateRecoveryCodes(33)).toThrow();
    expect(() => generateRecoveryCodes(1.5)).toThrow();
  });
});

describe("normalizeRecoveryCode", () => {
  it("strips whitespace and dashes, uppercases", () => {
    expect(normalizeRecoveryCode("abcd-efgh-ijkl")).toBe("ABCDEFGHIJKL");
    expect(normalizeRecoveryCode("  ab cd ef gh  ")).toBe("ABCDEFGH");
    expect(normalizeRecoveryCode("ABCD-EFGH-IJKL")).toBe("ABCDEFGHIJKL");
  });
});

describe("hashRecoveryCode", () => {
  it("is deterministic across equivalent inputs", () => {
    const a = hashRecoveryCode("ABCD-EFGH-IJKL");
    const b = hashRecoveryCode("abcd efgh-ijkl");
    expect(a).toBe(b);
  });

  it("produces a 64-char hex string", () => {
    expect(hashRecoveryCode("XXXX-YYYY-ZZZZ")).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("matchRecoveryCode", () => {
  it("returns the matching stored hash when the code is valid", () => {
    const codes = generateRecoveryCodes(3);
    const hashes = codes.map(hashRecoveryCode);
    const matched = matchRecoveryCode(codes[1]!, hashes);
    expect(matched).toBe(hashes[1]);
  });

  it("returns null for a code that is not present", () => {
    const hashes = generateRecoveryCodes(3).map(hashRecoveryCode);
    expect(matchRecoveryCode("AAAA-BBBB-CCCC", hashes)).toBeNull();
  });

  it("accepts user input with dashes stripped or lowercase", () => {
    const codes = generateRecoveryCodes(1);
    const hashes = codes.map(hashRecoveryCode);
    const stripped = codes[0]!.replace(/-/g, "").toLowerCase();
    expect(matchRecoveryCode(stripped, hashes)).toBe(hashes[0]);
  });
});
