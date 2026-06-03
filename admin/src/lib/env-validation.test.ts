import { describe, expect, it } from "vitest";

import {
  checkRequiredEnv,
  validateProductionEnv,
} from "./env-validation";

function validEnv(): NodeJS.ProcessEnv {
  return {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "x".repeat(48),
    SUPABASE_ANON_KEY: "y".repeat(32),
    MEDRASH_DEVICE_TOKEN_SECRET: "a".repeat(48),
    MEDRASH_ADMIN_SESSION_SECRET: "b".repeat(48),
    MEDRASH_TURNSTILE_SECRET: "turnstile-secret",
    NODE_ENV: "production",
  } as NodeJS.ProcessEnv;
}

describe("checkRequiredEnv", () => {
  it("returns no failures when every var is set", () => {
    expect(checkRequiredEnv(validEnv())).toEqual([]);
  });

  it("reports missing vars", () => {
    const env = validEnv();
    delete env.MEDRASH_TURNSTILE_SECRET;
    const failures = checkRequiredEnv(env);
    expect(failures).toEqual([
      { name: "MEDRASH_TURNSTILE_SECRET", reason: "missing" },
    ]);
  });

  it("reports short secrets", () => {
    const env = validEnv();
    env.MEDRASH_DEVICE_TOKEN_SECRET = "too-short";
    const failures = checkRequiredEnv(env);
    expect(failures).toContainEqual({
      name: "MEDRASH_DEVICE_TOKEN_SECRET",
      reason: "too_short",
      expectedMinLength: 32,
    });
  });
});

describe("validateProductionEnv", () => {
  it("is a no-op in development", () => {
    expect(() =>
      validateProductionEnv({ NODE_ENV: "development" } as NodeJS.ProcessEnv),
    ).not.toThrow();
  });

  it("is a no-op during next build", () => {
    expect(() =>
      validateProductionEnv({
        NODE_ENV: "production",
        NEXT_PHASE: "phase-production-build",
      } as NodeJS.ProcessEnv),
    ).not.toThrow();
  });

  it("throws in production when a secret is missing", () => {
    const env = validEnv();
    delete env.SUPABASE_SERVICE_ROLE_KEY;
    expect(() => validateProductionEnv(env)).toThrow(
      /SUPABASE_SERVICE_ROLE_KEY/,
    );
  });

  it("does not throw in production when every secret is valid", () => {
    expect(() => validateProductionEnv(validEnv())).not.toThrow();
  });
});
