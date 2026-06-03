/**
 * P0.3 (admin half) — environment variable validation.
 *
 * Production deploys MUST fail-fast at boot when a secret is missing rather
 * than crashing on the first request that needs it (and surfacing a
 * confusing "internal error" to a real user). Development and the Next.js
 * production-BUILD step are exempt because the build runs in CI without
 * Supabase credentials and the validators would block the bundle.
 *
 * Triggered from `admin/instrumentation.ts` for the Next.js nodejs runtime
 * and (separately) re-runnable by tests to assert the failure shape.
 *
 * Anything Supabase-adjacent reads its own var lazily through helpers in
 * `_shared/supabase.ts`, `_shared/device-token.ts`, etc., so the only
 * value-add of THIS validator is the up-front signal — it lets ops see
 * "MEDRASH_DEVICE_TOKEN_SECRET missing" in the boot log before the first
 * /api/login attempt.
 */

type EnvSpec = {
  /** Variable name. */
  name: string;
  /** Minimum length after trim; 0 = any non-empty value. */
  minLength?: number;
};

const REQUIRED_ENV: readonly EnvSpec[] = [
  { name: "SUPABASE_URL" },
  { name: "SUPABASE_SERVICE_ROLE_KEY", minLength: 32 },
  { name: "SUPABASE_ANON_KEY", minLength: 16 },
  { name: "MEDRASH_DEVICE_TOKEN_SECRET", minLength: 32 },
  { name: "MEDRASH_ADMIN_SESSION_SECRET", minLength: 32 },
  { name: "MEDRASH_TURNSTILE_SECRET" },
];

export type EnvValidationFailure = {
  name: string;
  reason: "missing" | "too_short";
  expectedMinLength?: number;
};

/** Validate the required env vars. Returns a list of failures (empty when
 * valid). Never throws — callers decide what to do with the result. */
export function checkRequiredEnv(
  env: NodeJS.ProcessEnv = process.env,
): EnvValidationFailure[] {
  const failures: EnvValidationFailure[] = [];
  for (const spec of REQUIRED_ENV) {
    const raw = env[spec.name];
    const value = typeof raw === "string" ? raw.trim() : "";
    if (value.length === 0) {
      failures.push({ name: spec.name, reason: "missing" });
      continue;
    }
    if (spec.minLength && value.length < spec.minLength) {
      failures.push({
        name: spec.name,
        reason: "too_short",
        expectedMinLength: spec.minLength,
      });
    }
  }
  return failures;
}

/** Throw a single, human-readable error listing every missing/short env var
 * IF the runtime is production. No-op during `next build` (NEXT_PHASE ===
 * "phase-production-build") so a CI bundle without secrets still builds. */
export function validateProductionEnv(
  env: NodeJS.ProcessEnv = process.env,
): void {
  if (env.NODE_ENV !== "production") return;
  if (env.NEXT_PHASE === "phase-production-build") return;

  const failures = checkRequiredEnv(env);
  if (failures.length === 0) return;

  const detail = failures
    .map((f) =>
      f.reason === "missing"
        ? `  - ${f.name}: missing`
        : `  - ${f.name}: must be at least ${f.expectedMinLength ?? 0} characters`,
    )
    .join("\n");
  throw new Error(
    `MedRash admin: required environment variables are not configured:\n${detail}\n\nRefer to docs/hosted-deploy.md for the full env-var checklist.`,
  );
}
