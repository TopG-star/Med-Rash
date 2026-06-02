import { SupabaseClient } from "@supabase/supabase-js";
import {
  getSupabaseAdminClient,
  parseIdentityInput,
  resolveOrCreateUserId,
  type IdentityInput,
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
import { leaderboardSchema } from "../../src/lib/schemas/leaderboard";
import { extractRemoteIp } from "./_shared/turnstile";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

type LeaderboardRowResponse = {
  rank: number;
  userId: string;
  /**
   * P7.5 — stable per-user seed for deterministic Navii avatars. Equals
   * the client-minted `identity_spine_id` (a.k.a. participantId) stored in
   * `users.metadata`. May be null for legacy rows whose metadata predates
   * the spine; clients fall back to `userId` for those.
   */
  seed: string | null;
  nickname: string;
  totalScore: number;
  rankedAttempts: number;
  lastRankedAt: string | null;
};

type RpcRow = {
  rank_position: number | string;
  user_id: string;
  nickname: string | null;
  total_score: number | string | null;
  ranked_attempts: number | string | null;
  last_ranked_at: string | null;
};

function readIdentityOrNull(body: Record<string, unknown>): IdentityInput | null {
  const pid = body.participantId;
  if (typeof pid !== "string" || pid.trim().length === 0) {
    return null;
  }
  try {
    return parseIdentityInput(body);
  } catch {
    return null;
  }
}

function mapRow(row: RpcRow): LeaderboardRowResponse {
  return {
    rank: Number(row.rank_position),
    userId: String(row.user_id),
    seed: null,
    nickname: String(row.nickname ?? ""),
    totalScore: Number(row.total_score ?? 0),
    rankedAttempts: Number(row.ranked_attempts ?? 0),
    lastRankedAt: row.last_ranked_at ?? null,
  };
}

/**
 * P7.5 — batch-fetch identity_spine_id for every user_id appearing in the
 * leaderboard response so each row carries the stable Navii seed. One
 * roundtrip per leaderboard call; users.id is the PK so the lookup is
 * effectively free. Returns a map of users.id → identity_spine_id; missing
 * entries (legacy rows) leave `seed` as null and the client falls back.
 */
async function fetchSeedsByUserId(
  supabase: SupabaseClient,
  userIds: ReadonlySet<string>,
): Promise<Map<string, string>> {
  const seedById = new Map<string, string>();
  if (userIds.size === 0) return seedById;
  const { data, error } = await supabase
    .from("users")
    .select("id, metadata")
    .in("id", [...userIds]);
  if (error) return seedById;
  for (const row of (data ?? []) as Array<{ id: string; metadata: unknown }>) {
    const meta = row.metadata as Record<string, unknown> | null;
    const seed = meta?.identity_spine_id;
    if (typeof seed === "string" && seed.length > 0) {
      seedById.set(String(row.id), seed);
    }
  }
  return seedById;
}

function attachSeed<T extends { userId: string; seed: string | null }>(
  row: T,
  seedById: Map<string, string>,
): T {
  const found = seedById.get(row.userId);
  return found ? { ...row, seed: found } : row;
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
    const validated = validateOrRespond(leaderboardSchema, body);
    if (!validated.ok) return validated.response;
    const type = validated.data.type;
    const limit = validated.data.limit;
    const seasonOverride = type === "monthly" ? validated.data.season : null;
    const identity = readIdentityOrNull(body);

    const supabase = getSupabaseAdminClient();

    // A6 — IP-keyed bucket (60/60s). Identity is optional on this endpoint
    // (anonymous leaderboard browsing is supported), so we always have an IP
    // but not always a participantId — IP is the only universal key here.
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

    let seasonKey: string | null = null;
    let topRows: RpcRow[] = [];

    if (type === "allTime") {
      const { data, error } = await supabase.rpc("leaderboard_all_time", {
        limit_count: limit,
      });
      if (error) {
        return jsonResponse(500, {
          ok: false,
          code: "LEADERBOARD_QUERY_FAILED",
          message: error.message,
        });
      }
      topRows = (data as RpcRow[] | null) ?? [];
    } else {
      const args: Record<string, unknown> = { limit_count: limit };
      if (seasonOverride) {
        args.season = seasonOverride;
      }
      const { data, error } = await supabase.rpc("leaderboard_monthly", args);
      if (error) {
        return jsonResponse(500, {
          ok: false,
          code: "LEADERBOARD_QUERY_FAILED",
          message: error.message,
        });
      }
      topRows = (data as RpcRow[] | null) ?? [];

      if (seasonOverride) {
        seasonKey = seasonOverride;
      } else {
        const { data: seasonData, error: seasonErr } = await supabase.rpc(
          "current_season_key_ghana",
        );
        if (seasonErr) {
          return jsonResponse(500, {
            ok: false,
            code: "SEASON_KEY_FAILED",
            message: seasonErr.message,
          });
        }
        if (typeof seasonData === "string") {
          seasonKey = seasonData;
        } else if (Array.isArray(seasonData) && seasonData.length > 0) {
          seasonKey = String(seasonData[0]);
        } else {
          seasonKey = null;
        }
      }
    }

    let meRow: LeaderboardRowResponse | null = null;
    if (identity) {
      const userId = await resolveOrCreateUserId(supabase, identity);
      let myData: RpcRow[] | null = null;

      if (type === "allTime") {
        const { data, error } = await supabase.rpc("my_rank_all_time", {
          target_user: userId,
        });
        if (error) {
          return jsonResponse(500, {
            ok: false,
            code: "MY_RANK_QUERY_FAILED",
            message: error.message,
          });
        }
        myData = (data as RpcRow[] | null) ?? [];
      } else {
        const args: Record<string, unknown> = { target_user: userId };
        if (seasonKey) {
          args.season = seasonKey;
        }
        const { data, error } = await supabase.rpc("my_rank_monthly", args);
        if (error) {
          return jsonResponse(500, {
            ok: false,
            code: "MY_RANK_QUERY_FAILED",
            message: error.message,
          });
        }
        myData = (data as RpcRow[] | null) ?? [];
      }

      if (myData && myData.length > 0) {
        meRow = mapRow(myData[0]);
      }
    }

    // P7.5 — hydrate the Navii avatar seed for every distinct user_id in
    // the response (top-N + optional "me" row) in a single batched fetch.
    const topMappedRaw = topRows.map(mapRow);
    const distinctIds = new Set<string>();
    topMappedRaw.forEach((r) => distinctIds.add(r.userId));
    if (meRow) distinctIds.add(meRow.userId);
    const seedById = await fetchSeedsByUserId(supabase, distinctIds);
    const topMapped = topMappedRaw.map((r) => attachSeed(r, seedById));
    if (meRow) meRow = attachSeed(meRow, seedById);

    return jsonResponse(200, {
      ok: true,
      type,
      seasonKey,
      limit,
      top: topMapped,
      me: meRow,
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
