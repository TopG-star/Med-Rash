import { getSupabaseAdminClient } from './_shared/supabase';
import { HandlerEvent, HandlerResponse, handlePreflight, jsonResponse, parseJsonBody, requirePost, toV2Handler } from './_shared/http';
import { requireGateAuthorization } from './_shared/gate';

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 30;
const MIN_RESPONSE_LATENCY_MS = 220;

type RateLimitBucket = {
  windowStartMs: number;
  requestCount: number;
};

const sessionResolveRateLimitBuckets = new Map<string, RateLimitBucket>();

type ResolvedSessionPayload = {
  sessionId: string;
  joinCode: string;
  quizId: string;
  title: string;
  category: string;
  topic: string;
  questionCount: number;
  timeLimit: string;
  host: string;
};

function parseJoinCode(body: Record<string, unknown>): string {
  const value = body.joinCode;
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error('joinCode is required.');
  }
  return value.trim().toUpperCase();
}

function readHeader(event: HandlerEvent, headerName: string): string {
  const headers = event.headers ?? {};
  const target = headerName.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() == target && typeof value == 'string') {
      return value;
    }
  }
  return '';
}

function readClientFingerprint(event: HandlerEvent): string {
  const netlifyIp = readHeader(event, 'x-nf-client-connection-ip').trim();
  if (netlifyIp.length > 0) {
    return `ip:${netlifyIp}`;
  }

  const forwarded = readHeader(event, 'x-forwarded-for').trim();
  if (forwarded.length > 0) {
    const first = forwarded.split(',')[0]?.trim() ?? '';
    if (first.length > 0) {
      return `ip:${first}`;
    }
  }

  return 'ip:unknown';
}

function isRateLimited(clientFingerprint: string): boolean {
  const nowMs = Date.now();
  const existing = sessionResolveRateLimitBuckets.get(clientFingerprint);

  if (!existing || nowMs - existing.windowStartMs >= RATE_LIMIT_WINDOW_MS) {
    sessionResolveRateLimitBuckets.set(clientFingerprint, {
      windowStartMs: nowMs,
      requestCount: 1,
    });
    return false;
  }

  existing.requestCount += 1;
  sessionResolveRateLimitBuckets.set(clientFingerprint, existing);
  return existing.requestCount > RATE_LIMIT_MAX_REQUESTS;
}

async function applyMinimumLatency(startedAtMs: number): Promise<void> {
  const elapsedMs = Date.now() - startedAtMs;
  if (elapsedMs >= MIN_RESPONSE_LATENCY_MS) {
    return;
  }

  await new Promise<void>((resolve) => {
    setTimeout(resolve, MIN_RESPONSE_LATENCY_MS - elapsedMs);
  });
}

function computeTimeLimit(questionCount: number): string {
  const minutes = Math.max(1, Math.ceil(questionCount / 2.5));
  return `${String(minutes).padStart(2, '0')}m`;
}

function buildSessionPayload(row: Record<string, unknown>): ResolvedSessionPayload {
  const rawQuiz = row.quizzes;
  const quiz = Array.isArray(rawQuiz)
    ? (rawQuiz[0] as Record<string, unknown> | undefined)
    : (rawQuiz as Record<string, unknown> | null);

  if (!quiz || typeof quiz !== 'object') {
    throw new Error('Session quiz relationship is missing.');
  }

  const questionCount =
    typeof quiz.question_count_default === 'number' && Number.isFinite(quiz.question_count_default)
      ? Math.max(1, Math.floor(quiz.question_count_default))
      : 5;

  const metadata =
    row.metadata && typeof row.metadata === 'object' && !Array.isArray(row.metadata)
      ? (row.metadata as Record<string, unknown>)
      : {};

  const metadataTimeLimit =
    typeof metadata.timeLimit === 'string' && metadata.timeLimit.trim().length > 0
      ? metadata.timeLimit.trim()
      : null;

  return {
    sessionId: String(row.id),
    joinCode: String(row.join_code),
    quizId: String(quiz.slug),
    title: typeof row.name === 'string' ? row.name : 'Live Session',
    category: typeof quiz.category === 'string' ? quiz.category : 'CME',
    topic: typeof quiz.summary === 'string' ? quiz.summary : 'Live clinical session',
    questionCount,
    timeLimit: metadataTimeLimit ?? computeTimeLimit(questionCount),
    host: typeof row.host_name === 'string' && row.host_name.trim().length > 0 ? row.host_name : 'Medical Team Lead',
  };
}

export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) {
    return preflight;
  }

  const methodResponse = requirePost(event);
  if (methodResponse) {
    return methodResponse;
  }

  const gateResponse = requireGateAuthorization(event);
  if (gateResponse) {
    return gateResponse;
  }

  const startedAtMs = Date.now();
  const clientFingerprint = readClientFingerprint(event);

  if (isRateLimited(clientFingerprint)) {
    await applyMinimumLatency(startedAtMs);
    return jsonResponse(429, {
      ok: false,
      code: 'RATE_LIMITED',
      message: 'Too many requests. Please retry shortly.',
    });
  }

  try {
    const body = parseJsonBody(event);
    const joinCode = parseJoinCode(body);
    const supabase = getSupabaseAdminClient();

    const { data, error } = await supabase
      .from('sessions')
      .select(
        `
        id,
        name,
        join_code,
        host_name,
        metadata,
        quizzes (
          slug,
          category,
          summary,
          question_count_default
        )
      `,
      )
      .eq('join_code', joinCode)
      .limit(1)
      .maybeSingle();

    if (error) {
      await applyMinimumLatency(startedAtMs);
      return jsonResponse(500, {
        ok: false,
        code: 'SESSION_RESOLVE_QUERY_FAILED',
        message: 'Unable to resolve session right now.',
      });
    }

    if (!data) {
      await applyMinimumLatency(startedAtMs);
      return jsonResponse(404, {
        ok: false,
        code: 'SESSION_NOT_FOUND',
        message: 'Session code not found.',
      });
    }

    const session = buildSessionPayload(data as Record<string, unknown>);

    await applyMinimumLatency(startedAtMs);
    return jsonResponse(200, {
      ok: true,
      session,
    });
  } catch {
    await applyMinimumLatency(startedAtMs);
    return jsonResponse(400, {
      ok: false,
      code: 'BAD_REQUEST',
      message: 'Invalid request.',
    });
  }
}

export default toV2Handler(handler);
