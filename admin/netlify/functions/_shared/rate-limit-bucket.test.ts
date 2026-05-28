import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { __resetBucketsForTests, consume } from "./rate-limit-bucket";

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  __resetBucketsForTests();
  process.env.MEDRASH_DEVICE_TOKEN_RATE_BURST = "3";
  process.env.MEDRASH_DEVICE_TOKEN_RATE_REFILL_PER_MIN = "60"; // 1 token/sec
  delete process.env.MEDRASH_DEVICE_TOKEN_RATE_DISABLED;
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("consume", () => {
  it("allows up to burst requests in a tight loop", () => {
    const now = 1_000_000;
    expect(consume("k", { nowMs: now }).allowed).toBe(true);
    expect(consume("k", { nowMs: now }).allowed).toBe(true);
    expect(consume("k", { nowMs: now }).allowed).toBe(true);
    const fourth = consume("k", { nowMs: now });
    expect(fourth.allowed).toBe(false);
    expect(fourth.retryAfterSeconds).toBeGreaterThan(0);
  });

  it("refills tokens at the configured rate", () => {
    const now = 1_000_000;
    consume("k", { nowMs: now });
    consume("k", { nowMs: now });
    consume("k", { nowMs: now });
    expect(consume("k", { nowMs: now }).allowed).toBe(false);
    // Refill 60 tokens/min = 1 token/sec. Wait 2s → 2 tokens back.
    expect(consume("k", { nowMs: now + 2_000 }).allowed).toBe(true);
    expect(consume("k", { nowMs: now + 2_000 }).allowed).toBe(true);
    expect(consume("k", { nowMs: now + 2_000 }).allowed).toBe(false);
  });

  it("keeps separate buckets per key", () => {
    const now = 1_000_000;
    consume("a", { nowMs: now });
    consume("a", { nowMs: now });
    consume("a", { nowMs: now });
    expect(consume("a", { nowMs: now }).allowed).toBe(false);
    expect(consume("b", { nowMs: now }).allowed).toBe(true);
  });

  it("bypasses entirely when MEDRASH_DEVICE_TOKEN_RATE_DISABLED is true", () => {
    process.env.MEDRASH_DEVICE_TOKEN_RATE_DISABLED = "true";
    const now = 1_000_000;
    for (let i = 0; i < 50; i += 1) {
      expect(consume("k", { nowMs: now }).allowed).toBe(true);
    }
  });

  it("falls back to defaults when env vars are missing", () => {
    delete process.env.MEDRASH_DEVICE_TOKEN_RATE_BURST;
    delete process.env.MEDRASH_DEVICE_TOKEN_RATE_REFILL_PER_MIN;
    const now = 1_000_000;
    // Default burst is 5.
    for (let i = 0; i < 5; i += 1) {
      expect(consume("k", { nowMs: now }).allowed).toBe(true);
    }
    expect(consume("k", { nowMs: now }).allowed).toBe(false);
  });

  it("never exceeds the burst cap on refill", () => {
    const now = 1_000_000;
    consume("k", { nowMs: now }); // 2 left
    // Jump way ahead — refill should cap at burst=3, not grow unbounded.
    const result = consume("k", { nowMs: now + 10_000_000 });
    expect(result.allowed).toBe(true);
    expect(result.remaining).toBeLessThanOrEqual(2);
  });
});
