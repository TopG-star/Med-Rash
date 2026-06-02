import { z } from "zod";
import {
  getSupabaseAdminClient,
  parseIdentityInput,
  resolveOrCreateUserId,
} from "./_shared/supabase";
import {
  HandlerEvent,
  HandlerResponse,
  handlePreflight,
  jsonResponse,
  parseJsonBody,
  requirePost,
  toV2Handler,
} from "./_shared/http";
import { requireParticipantAuth } from "./_shared/participant-auth";
import { validateOrRespond } from "./_shared/validate";
import { extractRemoteIp } from "./_shared/turnstile";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";
import { profileSchema } from "../../src/lib/schemas/identity";
import {
  nonEmptyTrimmed,
  optionalTrimmedNullable,
} from "../../src/lib/schemas/_helpers";

// P8.c — pilot target for monthly ranked attempts. Surfaced in the
// donut as the denominator so participants always see a clear goal
// regardless of completion count. Lives server-side so future tuning
// doesn't require a client rebuild.
const MONTHLY_ATTEMPT_TARGET = 20;

// Cap on per-category rows returned. Keeps the bar chart legible and
// the payload bounded.
const MAX_CATEGORY_ROWS = 6;

const participantStatsSchema = z.object({
  participantId: nonEmptyTrimmed("participantId", 128),
  deviceInstallId: nonEmptyTrimmed("deviceInstallId", 256),
  profile: profileSchema.optional(),
  // Reserved for future expansion (weekly/yearly). Pilot only honors
  // 'monthly'; anything else falls through to monthly behavior.
  period: optionalTrimmedNullable(16),
});

type AttemptRow = {
  score: number | string | null;
  total_questions: number | string | null;
  completed_at: string | null;
  // PostgREST embedded relation — quizzes is the joined row.
  quizzes: { category: string | null } | null;
};

type CategoryAccumulator = {
  category: string;
  correctSum: number;
  totalSum: number;
  attempts: number;
};

function startOfCurrentMonthIsoUtc(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
}

export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) return preflight;

  const methodError = requirePost(event);
  if (methodError) return methodError;

  const auth = requireParticipantAuth(event);
  if (!auth.ok) return auth.response;

  try {
    const body = parseJsonBody(event);
    const validated = validateOrRespond(participantStatsSchema, body);
    if (!validated.ok) return validated.response;

    const identity = parseIdentityInput(body);
    const supabase = getSupabaseAdminClient();

    // IP-keyed rate limit mirrors the leaderboard endpoint cadence; stats
    // is a cheap read but still hits the DB so we cap noisy clients.
    const clientIp = extractRemoteIp(event.headers) ?? "unknown-ip";
    const ipLimit = await enforceRateLimit(
      supabase,
      rateLimitConfig("leaderboard", clientIp),
    );
    if (!ipLimit.allowed) {
      return jsonResponse(429, {
        ok: false,
        code: "RATE_LIMITED",
        message: formatLockoutMessage(ipLimit),
        retryAfterSeconds: ipLimit.retryAfterSeconds,
      });
    }

    const userId = await resolveOrCreateUserId(supabase, identity);
    const monthStart = startOfCurrentMonthIsoUtc();

    // Single read: every completed attempt for this user joined to the
    // quiz row so we can group by category. completed_at is filtered to
    // current-month in JS for the donut count while the bar chart uses
    // the full sweep so newcomers still see meaningful bars.
    const { data, error } = await supabase
      .from("attempts")
      .select("score, total_questions, completed_at, quizzes(category)")
      .eq("user_id", userId)
      .not("completed_at", "is", null);

    if (error) {
      return jsonResponse(500, {
        ok: false,
        code: "STATS_QUERY_FAILED",
        message: error.message,
      });
    }

    const rows = (data ?? []) as unknown as AttemptRow[];

    let monthlyAttempts = 0;
    const byCategory = new Map<string, CategoryAccumulator>();

    for (const row of rows) {
      const completedAt = row.completed_at;
      const score = Number(row.score ?? 0);
      const total = Number(row.total_questions ?? 0);
      if (total <= 0) continue;

      if (completedAt && completedAt >= monthStart) {
        monthlyAttempts += 1;
      }

      const category = row.quizzes?.category?.trim();
      if (!category) continue;
      const acc = byCategory.get(category) ?? {
        category,
        correctSum: 0,
        totalSum: 0,
        attempts: 0,
      };
      acc.correctSum += score;
      acc.totalSum += total;
      acc.attempts += 1;
      byCategory.set(category, acc);
    }

    const accuracyByCategory = [...byCategory.values()]
      .map((c) => ({
        category: c.category,
        accuracyPct:
          c.totalSum > 0 ? Math.round((c.correctSum / c.totalSum) * 100) : 0,
        attempts: c.attempts,
      }))
      .sort((a, b) => b.attempts - a.attempts)
      .slice(0, MAX_CATEGORY_ROWS);

    return jsonResponse(200, {
      ok: true,
      monthlyAttempts,
      monthlyTarget: MONTHLY_ATTEMPT_TARGET,
      accuracyByCategory,
      generatedAt: new Date().toISOString(),
    });
  } catch (err) {
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: err instanceof Error ? err.message : "Invalid request.",
    });
  }
}

export default toV2Handler(handler);
