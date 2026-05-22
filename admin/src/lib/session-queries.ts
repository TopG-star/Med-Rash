import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type AdminSessionRow = {
  id: string;
  name: string;
  joinCode: string;
  hostName: string | null;
  startsAt: string | null;
  endsAt: string | null;
  createdAt: string;
  quizId: string;
  quizTitle: string;
  attemptCount: number;
  isActiveNow: boolean;
};

export type AdminQuizOption = {
  id: string;
  title: string;
  slug: string;
};

type SessionRow = {
  id: string;
  name: string;
  join_code: string;
  host_name: string | null;
  starts_at: string | null;
  ends_at: string | null;
  created_at: string;
  quiz_id: string;
  quizzes:
    | { title: string | null }
    | Array<{ title: string | null }>
    | null;
  attempts: Array<{ id: string }> | null;
};

function isActiveNow(
  startsAt: string | null,
  endsAt: string | null,
  nowMs: number,
): boolean {
  const startMs = startsAt ? Date.parse(startsAt) : Number.NEGATIVE_INFINITY;
  const endMs = endsAt ? Date.parse(endsAt) : Number.POSITIVE_INFINITY;
  return nowMs >= startMs && nowMs <= endMs;
}

/**
 * List sessions newest-first with attached quiz title and a count of attempts.
 * Active = current time is within [starts_at, ends_at]; null bounds are open.
 */
export async function listAdminSessions(): Promise<AdminSessionRow[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("sessions")
    .select(
      "id, name, join_code, host_name, starts_at, ends_at, created_at, quiz_id, quizzes(title), attempts(id)",
    )
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    throw new Error(`Failed to load sessions: ${error.message}`);
  }

  const rows = (data as SessionRow[] | null) ?? [];
  const nowMs = Date.now();

  return rows.map((row) => {
    const quizRel = Array.isArray(row.quizzes) ? row.quizzes[0] : row.quizzes;
    return {
      id: row.id,
      name: row.name,
      joinCode: row.join_code,
      hostName: row.host_name,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      createdAt: row.created_at,
      quizId: row.quiz_id,
      quizTitle: quizRel?.title ?? "(unknown quiz)",
      attemptCount: (row.attempts ?? []).length,
      isActiveNow: isActiveNow(row.starts_at, row.ends_at, nowMs),
    };
  });
}

type QuizOptionRow = {
  id: string;
  title: string;
  slug: string;
  is_active: boolean | null;
};

/**
 * Active quizzes available for new sessions, ordered by title.
 */
export async function listActiveQuizOptions(): Promise<AdminQuizOption[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("quizzes")
    .select("id, title, slug, is_active")
    .eq("is_active", true)
    .order("title", { ascending: true });

  if (error) {
    throw new Error(`Failed to load quizzes: ${error.message}`);
  }

  const rows = (data as QuizOptionRow[] | null) ?? [];
  return rows.map((row) => ({ id: row.id, title: row.title, slug: row.slug }));
}

export type SessionLiveTopRow = {
  participantId: string;
  displayName: string;
  facility: string | null;
  score: number;
  totalQuestions: number;
  completedAt: string;
};

export type SessionLiveSnapshot = {
  sessionId: string;
  name: string;
  joinCode: string;
  quizTitle: string;
  isActiveNow: boolean;
  joined: number;
  /**
   * Distinct participants who successfully resolved the join code (i.e. landed
   * on /session/<code>). May exceed `joined` when participants scanned but
   * never started/submitted an attempt — surfaces blocked/abandoned scans.
   */
  scanned: number;
  submitted: number;
  lastActivityAt: string | null;
  top5: SessionLiveTopRow[];
};

type LiveAttemptRow = {
  id: string;
  user_id: string;
  score: number | null;
  total_questions: number | null;
  completed_at: string | null;
  started_at: string | null;
  users:
    | { nickname: string | null; full_name: string | null; facility: string | null }
    | Array<{ nickname: string | null; full_name: string | null; facility: string | null }>
    | null;
};

type LiveSessionHeader = {
  id: string;
  name: string;
  join_code: string;
  starts_at: string | null;
  ends_at: string | null;
  quizzes: { title: string | null } | Array<{ title: string | null }> | null;
};

/**
 * Live projector snapshot for a single session.
 * `joined` counts unique participants with any attempt row.
 * `submitted` counts attempts that have completed_at set.
 * `top5` lists the highest-scoring completed attempts.
 */
export async function getSessionLiveSnapshot(
  sessionId: string,
): Promise<SessionLiveSnapshot | null> {
  const supabase = getAdminSupabaseClient();

  const { data: headerData, error: headerError } = await supabase
    .from("sessions")
    .select("id, name, join_code, starts_at, ends_at, quizzes(title)")
    .eq("id", sessionId)
    .maybeSingle();

  if (headerError) {
    throw new Error(`Failed to load session: ${headerError.message}`);
  }
  if (!headerData) {
    return null;
  }
  const header = headerData as LiveSessionHeader;

  const { data: attemptsData, error: attemptsError } = await supabase
    .from("attempts")
    .select(
      "id, user_id, score, total_questions, completed_at, started_at, users(nickname, full_name, facility)",
    )
    .eq("session_id", sessionId)
    .order("completed_at", { ascending: false, nullsFirst: false })
    .limit(500);

  if (attemptsError) {
    throw new Error(`Failed to load attempts: ${attemptsError.message}`);
  }

  const { count: scannedCountRaw, error: scannedError } = await supabase
    .from("session_join_events")
    .select("id", { count: "exact", head: true })
    .eq("session_id", sessionId);

  if (scannedError) {
    throw new Error(`Failed to load join events: ${scannedError.message}`);
  }
  const scanned = scannedCountRaw ?? 0;

  const attempts = (attemptsData as LiveAttemptRow[] | null) ?? [];
  const uniqueUsers = new Set<string>();
  let submitted = 0;
  let lastActivityMs = 0;

  for (const a of attempts) {
    uniqueUsers.add(a.user_id);
    if (a.completed_at) {
      submitted += 1;
      const t = Date.parse(a.completed_at);
      if (Number.isFinite(t) && t > lastActivityMs) lastActivityMs = t;
    } else if (a.started_at) {
      const t = Date.parse(a.started_at);
      if (Number.isFinite(t) && t > lastActivityMs) lastActivityMs = t;
    }
  }

  const completed = attempts.filter((a) => a.completed_at !== null);
  completed.sort((a, b) => {
    const sa = a.score ?? 0;
    const sb = b.score ?? 0;
    if (sb !== sa) return sb - sa;
    const ta = Date.parse(a.completed_at ?? "") || 0;
    const tb = Date.parse(b.completed_at ?? "") || 0;
    return ta - tb;
  });

  const top5: SessionLiveTopRow[] = completed.slice(0, 5).map((a) => {
    const rel = Array.isArray(a.users) ? a.users[0] : a.users;
    const nickname = rel?.nickname?.trim();
    const fullName = rel?.full_name?.trim();
    const displayName =
      (nickname && nickname.length > 0 ? nickname : null) ??
      (fullName && fullName.length > 0 ? fullName : null) ??
      "Anonymous";
    return {
      participantId: a.user_id,
      displayName,
      facility: rel?.facility ?? null,
      score: a.score ?? 0,
      totalQuestions: a.total_questions ?? 0,
      completedAt: a.completed_at ?? "",
    };
  });

  const quizRel = Array.isArray(header.quizzes) ? header.quizzes[0] : header.quizzes;
  const nowMs = Date.now();

  return {
    sessionId: header.id,
    name: header.name,
    joinCode: header.join_code,
    quizTitle: quizRel?.title ?? "(unknown quiz)",
    isActiveNow: isActiveNow(header.starts_at, header.ends_at, nowMs),
    joined: uniqueUsers.size,
    scanned,
    submitted,
    lastActivityAt: lastActivityMs > 0 ? new Date(lastActivityMs).toISOString() : null,
    top5,
  };
}
