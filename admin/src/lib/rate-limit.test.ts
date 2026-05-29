import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  enforceRateLimit,
  rateLimitConfig,
  resetRateLimit,
} from "./rate-limit";

// Fake Supabase client that simulates the Postgres-side enforce_rate_limit
// function in TypeScript. The real RPC is exercised in
// supabase/migrations/013_auth_rate_limit.sql; here we only verify that
// the TS wrapper interprets RPC responses correctly and that the four
// invariants from plan §3 slice A1 hold against an in-memory analogue:
//   1. First hit allowed
//   2. Nth hit (where N = limit + 1) denied
//   3. Lockout window respected
//   4. Window reset after windowSeconds elapses

type Row = {
  windowStartedAt: number;
  attemptCount: number;
  lockedUntil: number | null;
};

function buildFakeClient(now: () => number) {
  const store = new Map<string, Row>();

  return {
    store,
    rpc(name: string, params: Record<string, unknown>) {
      if (name === "enforce_rate_limit") {
        const key = params.p_key as string;
        const limit = params.p_limit as number;
        const windowSec = params.p_window_seconds as number;
        const lockoutSec = params.p_lockout_seconds as number;
        const t = now();

        let row = store.get(key);
        if (!row) {
          row = { windowStartedAt: t, attemptCount: 0, lockedUntil: null };
          store.set(key, row);
        }

        if (row.lockedUntil !== null && row.lockedUntil > t) {
          return Promise.resolve({
            data: [
              {
                allowed: false,
                attempts_remaining: 0,
                retry_after_seconds: Math.max(
                  1,
                  Math.ceil((row.lockedUntil - t) / 1000),
                ),
                locked_until: new Date(row.lockedUntil).toISOString(),
              },
            ],
            error: null,
          });
        }

        const windowEnd = row.windowStartedAt + windowSec * 1000;
        if (windowEnd <= t) {
          row.windowStartedAt = t;
          row.attemptCount = 0;
          row.lockedUntil = null;
        }

        row.attemptCount += 1;

        if (row.attemptCount > limit) {
          row.lockedUntil = t + lockoutSec * 1000;
          return Promise.resolve({
            data: [
              {
                allowed: false,
                attempts_remaining: 0,
                retry_after_seconds: Math.max(
                  1,
                  Math.ceil((row.lockedUntil - t) / 1000),
                ),
                locked_until: new Date(row.lockedUntil).toISOString(),
              },
            ],
            error: null,
          });
        }

        return Promise.resolve({
          data: [
            {
              allowed: true,
              attempts_remaining: Math.max(0, limit - row.attemptCount),
              retry_after_seconds: 0,
              locked_until: null,
            },
          ],
          error: null,
        });
      }

      if (name === "reset_rate_limit") {
        store.delete(params.p_key as string);
        return Promise.resolve({ data: null, error: null });
      }

      return Promise.resolve({
        data: null,
        error: { message: `unexpected rpc ${name}` },
      });
    },
  };
}

describe("enforceRateLimit", () => {
  let currentMs = 0;
  const now = () => currentMs;

  beforeEach(() => {
    currentMs = Date.UTC(2025, 0, 1, 0, 0, 0);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("allows the first attempt and counts down attemptsRemaining", async () => {
    const fake = buildFakeClient(now);
    const cfg = rateLimitConfig("auth_otp_verify", "user@example.com");

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const first = await enforceRateLimit(fake as any, cfg);
    expect(first.allowed).toBe(true);
    expect(first.attemptsRemaining).toBe(cfg.limit - 1);
    expect(first.lockedUntil).toBeNull();
  });

  it("denies the (limit+1)th attempt and reports a retry window", async () => {
    const fake = buildFakeClient(now);
    const cfg = rateLimitConfig("auth_otp_verify", "user@example.com");

    for (let i = 0; i < cfg.limit; i += 1) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const ok = await enforceRateLimit(fake as any, cfg);
      expect(ok.allowed).toBe(true);
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const denied = await enforceRateLimit(fake as any, cfg);
    expect(denied.allowed).toBe(false);
    expect(denied.attemptsRemaining).toBe(0);
    expect(denied.retryAfterSeconds).toBeGreaterThan(0);
    expect(denied.lockedUntil).toBeInstanceOf(Date);
  });

  it("keeps denying while the lockout window is active", async () => {
    const fake = buildFakeClient(now);
    const cfg = rateLimitConfig("auth_otp_verify", "user@example.com");

    for (let i = 0; i <= cfg.limit; i += 1) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await enforceRateLimit(fake as any, cfg);
    }

    currentMs += 5 * 60_000; // 5 minutes into a 15-minute lockout

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const stillDenied = await enforceRateLimit(fake as any, cfg);
    expect(stillDenied.allowed).toBe(false);
    expect(stillDenied.retryAfterSeconds).toBeGreaterThan(0);
  });

  it("resets the window once windowSeconds elapses", async () => {
    const fake = buildFakeClient(now);
    const cfg = rateLimitConfig("auth_otp_verify", "user@example.com");

    for (let i = 0; i <= cfg.limit; i += 1) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await enforceRateLimit(fake as any, cfg);
    }

    currentMs += (cfg.windowSeconds + cfg.lockoutSeconds + 1) * 1000;

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const fresh = await enforceRateLimit(fake as any, cfg);
    expect(fresh.allowed).toBe(true);
    expect(fresh.attemptsRemaining).toBe(cfg.limit - 1);
  });

  it("resetRateLimit clears a key so subsequent attempts start fresh", async () => {
    const fake = buildFakeClient(now);
    const cfg = rateLimitConfig("auth_otp_verify", "user@example.com");

    for (let i = 0; i < cfg.limit; i += 1) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await enforceRateLimit(fake as any, cfg);
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await resetRateLimit(fake as any, cfg.scope, cfg.identifier);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const fresh = await enforceRateLimit(fake as any, cfg);
    expect(fresh.allowed).toBe(true);
    expect(fresh.attemptsRemaining).toBe(cfg.limit - 1);
  });

  it("hashes identifiers so the underlying key never stores the raw email", async () => {
    const fake = buildFakeClient(now);
    const cfg = rateLimitConfig("auth_otp_verify", "user@example.com");

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await enforceRateLimit(fake as any, cfg);

    const storedKeys = Array.from(fake.store.keys());
    expect(storedKeys).toHaveLength(1);
    expect(storedKeys[0]).toMatch(/^auth_otp_verify:[a-f0-9]{64}$/);
    expect(storedKeys[0]).not.toContain("user@example.com");
  });

  it("treats identifier case and whitespace as equivalent", async () => {
    const fake = buildFakeClient(now);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await enforceRateLimit(fake as any, rateLimitConfig("auth_otp_verify", "USER@example.com "));
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const second = await enforceRateLimit(fake as any, rateLimitConfig("auth_otp_verify", "user@example.com"));

    expect(fake.store.size).toBe(1);
    expect(second.attemptsRemaining).toBe(rateLimitConfig("auth_otp_verify", "x").limit - 2);
  });

  // Slice A6 — verify every newly added scope has a config so a typo in the
  // RATE_LIMITS table can't make `rateLimitConfig(scope, id)` return undefined
  // fields at runtime (TypeScript already guards against missing keys at
  // compile time, but a wrong-value entry like 0/0/0 would silently allow
  // every request through).
  it("returns plan-spec defaults for every A6 scope", () => {
    const cases: Array<[
      "attempt_submit" | "attempt_submit_ip" | "profile_sync" |
      "ranked_eligibility" | "leaderboard" | "quiz_list" |
      "quiz_bank_write" | "session_create",
      { limit: number; windowSeconds: number; lockoutSeconds: number },
    ]> = [
      ["attempt_submit",      { limit: 60,  windowSeconds: 60, lockoutSeconds: 60 }],
      ["attempt_submit_ip",   { limit: 600, windowSeconds: 60, lockoutSeconds: 60 }],
      ["profile_sync",        { limit: 30,  windowSeconds: 60, lockoutSeconds: 60 }],
      ["ranked_eligibility",  { limit: 120, windowSeconds: 60, lockoutSeconds: 60 }],
      ["leaderboard",         { limit: 60,  windowSeconds: 60, lockoutSeconds: 60 }],
      ["quiz_list",           { limit: 60,  windowSeconds: 60, lockoutSeconds: 60 }],
      ["quiz_bank_write",     { limit: 30,  windowSeconds: 60, lockoutSeconds: 60 }],
      ["session_create",      { limit: 30,  windowSeconds: 60, lockoutSeconds: 60 }],
    ];

    for (const [scope, expected] of cases) {
      const cfg = rateLimitConfig(scope, "x");
      expect(cfg.scope, scope).toBe(scope);
      expect(cfg.limit, `${scope} limit`).toBe(expected.limit);
      expect(cfg.windowSeconds, `${scope} window`).toBe(expected.windowSeconds);
      expect(cfg.lockoutSeconds, `${scope} lockout`).toBe(expected.lockoutSeconds);
    }
  });
});
