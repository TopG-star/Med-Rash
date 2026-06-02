import { SupabaseClient } from "@supabase/supabase-js";
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
import { sessionLeaderboardSchema } from "../../src/lib/schemas/session";
import { extractRemoteIp } from "./_shared/turnstile";
import {
  enforceRateLimit,
  formatLockoutMessage,
  rateLimitConfig,
} from "../../src/lib/rate-limit";

type SessionLeaderboardRowResponse = {
  rank: number;
  userId: string;
  /**
   * P7.5 — stable per-user seed for deterministic Navii avatars. Equals
   * the client-minted `identity_spine_id` (a.k.a. participantId) stored in
   * `users.metadata`. May be null for legacy rows; clients fall back to
   * `userId` for those.
   */
  seed: string | null;
  nickname: string;
  sessionScore: number;
  timeTakenMs: number;
  completedAt: string | null;
};

type RpcRow = {
  rank_position: number | string;
  user_id: string;
  nickname: string | null;
  session_score: number | string | null;
  time_taken_ms: number | string | null;
  completed_at: string | null;
};

type SessionHeaderRow = {
  id: string;
  starts_at: string | null;
  ends_at: string | null;
  closed_at: string | null;
};

function mapRow(row: RpcRow): SessionLeaderboardRowResponse {
  return {
    rank: Number(row.rank_position),
    userId: String(row.user_id),
    seed: null,
    nickname: String(row.nickname ?? ""),
    sessionScore: Number(row.session_score ?? 0),
    timeTakenMs: Number(row.time_taken_ms ?? 0),
    completedAt: row.completed_at ?? null,
  };
}

/**
 * P7.5 — see leaderboard.ts for the rationale. Single roundtrip per
 * session-leaderboard call; users.id is the PK.
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

function deriveIsLive(header: SessionHeaderRow, nowMs: number): boolean {
  if (header.closed_at !== null) return false;
  const startMs = header.starts_at ? Date.parse(header.starts_at) : null;
  const endMs = header.ends_at ? Date.parse(header.ends_at) : null;
  if (startMs !== null && Number.isFinite(startMs) && nowMs < startMs) {
    return false;
  }
  if (endMs !== null && Number.isFinite(endMs) && nowMs > endMs) {
    return false;
  }
  return true;
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
    const validated = validateOrRespond(sessionLeaderboardSchema, body);
    if (!validated.ok) return validated.response;
    const { sessionId, limit } = validated.data;

    const identity = parseIdentityInput(body);
    const supabase = getSupabaseAdminClient();

    // IP-keyed rate limit — first line of defence against a misbehaving
    // poller. Identity-keyed limiting would conflate every device behind a
    // single venue NAT; we accept the looser shape and lean on the per-IP
    // ceiling for runaway clients.
    const clientIp = extractRemoteIp(event.headers) ?? "unknown-ip";
    const ipLimit = await enforceRateLimit(
      supabase,
      rateLimitConfig("session_leaderboard", clientIp),
    );
    if (!ipLimit.allowed) {
      return jsonResponse(429, {
        ok: false,
        code: "RATE_LIMITED",
        message: formatLockoutMessage(ipLimit),
        retryAfterSeconds: ipLimit.retryAfterSeconds,
      });
    }

    // Resolve the session header first so we can short-circuit with a clean
    // 404 if the sessionId is wrong/stale, before we ever touch the user
    // resolver (which writes a users row on first touch).
    const { data: headerRaw, error: headerErr } = await supabase
      .from("sessions")
      .select("id, starts_at, ends_at, closed_at")
      .eq("id", sessionId)
      .maybeSingle();
    if (headerErr) {
      return jsonResponse(500, {
        ok: false,
        code: "SESSION_LOOKUP_FAILED",
        message: headerErr.message,
      });
    }
    if (!headerRaw) {
      return jsonResponse(404, {
        ok: false,
        code: "SESSION_NOT_FOUND",
        message: "Session not found.",
      });
    }
    const header = headerRaw as SessionHeaderRow;
    const isLive = deriveIsLive(header, Date.now());

    const requestingUserId = await resolveOrCreateUserId(supabase, identity);

    // Option C membership probe: at least one attempt for this user in this
    // session. Cheap (indexed by attempts_session_idx + filtered by user_id),
    // and naturally excludes drive-by QR scanners who never played.
    const { count: membershipCount, error: membershipErr } = await supabase
      .from("attempts")
      .select("id", { count: "exact", head: true })
      .eq("session_id", sessionId)
      .eq("user_id", requestingUserId);
    if (membershipErr) {
      return jsonResponse(500, {
        ok: false,
        code: "MEMBERSHIP_LOOKUP_FAILED",
        message: membershipErr.message,
      });
    }
    if ((membershipCount ?? 0) === 0) {
      return jsonResponse(403, {
        ok: false,
        code: "NOT_SESSION_PARTICIPANT",
        message:
          "Play the session quiz first to see where you rank on this session's leaderboard.",
        isLive,
        endsAt: header.ends_at,
        closedAt: header.closed_at,
      });
    }

    const { data: topData, error: topErr } = await supabase.rpc(
      "session_leaderboard",
      {
        target_session: sessionId,
        limit_count: limit,
      },
    );
    if (topErr) {
      return jsonResponse(500, {
        ok: false,
        code: "SESSION_LEADERBOARD_QUERY_FAILED",
        message: topErr.message,
      });
    }
    const topRows = (topData as RpcRow[] | null) ?? [];

    // Always fetch "me" so the client can self-highlight even when the user
    // fell off the top-N list. Same RPC family pattern as the global board.
    const { data: meData, error: meErr } = await supabase.rpc(
      "my_session_rank",
      {
        target_session: sessionId,
        target_user: requestingUserId,
      },
    );
    if (meErr) {
      return jsonResponse(500, {
        ok: false,
        code: "MY_SESSION_RANK_QUERY_FAILED",
        message: meErr.message,
      });
    }
    const meRows = (meData as RpcRow[] | null) ?? [];
    let meRow = meRows.length > 0 ? mapRow(meRows[0]) : null;

    // P7.5 — hydrate the Navii avatar seed for every distinct user_id in
    // the response (top-N + optional "me" row) in one batched fetch.
    const topMappedRaw = topRows.map(mapRow);
    const distinctIds = new Set<string>();
    topMappedRaw.forEach((r) => distinctIds.add(r.userId));
    if (meRow) distinctIds.add(meRow.userId);
    const seedById = await fetchSeedsByUserId(supabase, distinctIds);
    const topMapped = topMappedRaw.map((r) => attachSeed(r, seedById));
    if (meRow) meRow = attachSeed(meRow, seedById);

    return jsonResponse(200, {
      ok: true,
      sessionId,
      isLive,
      endsAt: header.ends_at,
      closedAt: header.closed_at,
      requestingUserId,
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
