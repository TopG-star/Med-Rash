import {
  getSupabaseAdminClient,
  parseIdentityInput,
  resolveOrCreateUserId,
  type IdentityInput,
} from "./_shared/supabase";
import {
  HandlerEvent,
  HandlerResponse,
  jsonResponse,
  parseJsonBody,
  requirePost,
} from "./_shared/http";
import { requireGateAuthorization } from "./_shared/gate";

type LeaderboardType = "monthly" | "allTime";

type LeaderboardRowResponse = {
  rank: number;
  userId: string;
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

function readType(body: Record<string, unknown>): LeaderboardType {
  const raw = typeof body.type === "string" ? body.type.trim() : "";
  if (raw === "monthly" || raw === "allTime") {
    return raw as LeaderboardType;
  }
  return "allTime";
}

function readLimit(body: Record<string, unknown>): number {
  const raw = body.limit;
  const n = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isFinite(n) || n <= 0) {
    return 50;
  }
  return Math.min(Math.max(Math.floor(n), 1), 100);
}

function readSeason(body: Record<string, unknown>): string | null {
  const raw = typeof body.season === "string" ? body.season.trim() : "";
  if (/^\d{4}-\d{2}$/.test(raw)) {
    return raw;
  }
  return null;
}

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
    nickname: String(row.nickname ?? ""),
    totalScore: Number(row.total_score ?? 0),
    rankedAttempts: Number(row.ranked_attempts ?? 0),
    lastRankedAt: row.last_ranked_at ?? null,
  };
}

export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const methodError = requirePost(event);
  if (methodError) return methodError;

  const gateError = requireGateAuthorization(event);
  if (gateError) return gateError;

  try {
    const body = parseJsonBody(event);
    const type = readType(body);
    const limit = readLimit(body);
    const seasonOverride = type === "monthly" ? readSeason(body) : null;
    const identity = readIdentityOrNull(body);

    const supabase = getSupabaseAdminClient();

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

    return jsonResponse(200, {
      ok: true,
      type,
      seasonKey,
      limit,
      top: topRows.map(mapRow),
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

export default handler;
