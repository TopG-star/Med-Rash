import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type AdminSessionRow = {
  id: string;
  name: string;
  joinCode: string;
  hostName: string | null;
  startsAt: string | null;
  endsAt: string | null;
  closedAt: string | null;
  createdAt: string;
  createdBy: string | null;
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

/**
 * Visibility scope for the Sessions list.
 *   - "mine" filters created_by = userId
 *   - "all"  returns every row (still subject to the admin allowlist gate)
 */
export type ListScope = {
  scope: "mine" | "all";
  userId: string;
};

type SessionRow = {
  id: string;
  name: string;
  join_code: string;
  host_name: string | null;
  starts_at: string | null;
  ends_at: string | null;
  closed_at: string | null;
  created_at: string;
  created_by: string | null;
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
  closedAt: string | null,
  nowMs: number,
): boolean {
  if (closedAt) return false;
  const startMs = startsAt ? Date.parse(startsAt) : Number.NEGATIVE_INFINITY;
  const endMs = endsAt ? Date.parse(endsAt) : Number.POSITIVE_INFINITY;
  return nowMs >= startMs && nowMs <= endMs;
}

/**
 * List sessions newest-first with attached quiz title and a count of attempts.
 * Active = current time is within [starts_at, ends_at]; null bounds are open.
 * When `filter.scope === "mine"`, only rows whose created_by matches the
 * current admin are returned.
 */
export async function listAdminSessions(
  filter: ListScope = { scope: "all", userId: "" },
): Promise<AdminSessionRow[]> {
  const supabase = getAdminSupabaseClient();
  let query = supabase
    .from("sessions")
    .select(
      "id, name, join_code, host_name, starts_at, ends_at, closed_at, created_at, created_by, quiz_id, quizzes(title), attempts(id)",
    )
    .order("created_at", { ascending: false })
    .limit(50);

  if (filter.scope === "mine") {
    if (!filter.userId) return [];
    query = query.eq("created_by", filter.userId);
  }

  const { data, error } = await query;

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
      closedAt: row.closed_at,
      createdAt: row.created_at,
      createdBy: row.created_by,
      quizId: row.quiz_id,
      quizTitle: quizRel?.title ?? "(unknown quiz)",
      attemptCount: (row.attempts ?? []).length,
      isActiveNow: isActiveNow(row.starts_at, row.ends_at, row.closed_at, nowMs),
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

/**
 * Aggregate per-question distribution across every answer submitted in this
 * session. Drives the host control room's distribution bars.
 * `optionCounts[i]` = number of participants who picked option index `i`.
 */
export type SessionLiveQuestionStat = {
  questionId: string;
  prompt: string;
  options: string[];
  correctIndex: number;
  totalAnswers: number;
  optionCounts: number[];
};

export type SessionLiveSnapshot = {
  sessionId: string;
  name: string;
  joinCode: string;
  hostName: string | null;
  startsAt: string | null;
  endsAt: string | null;
  closedAt: string | null;
  quizTitle: string;
  totalQuestions: number;
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
  /**
   * Every completed attempt for this session ordered by score desc then
   * earliest completion. `top5` is the first five rows of this list — the
   * recap surface consumes the full list for final standings + CSV export.
   */
  standings: SessionLiveTopRow[];
  perQuestion: SessionLiveQuestionStat[];
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
  host_name: string | null;
  quiz_id: string;
  starts_at: string | null;
  ends_at: string | null;
  closed_at: string | null;
  quizzes: { title: string | null } | Array<{ title: string | null }> | null;
};

type LiveQuestionRow = {
  id: string;
  prompt: string;
  options: unknown;
  correct_index: number;
  position: number | null;
};

type LiveAnswerRow = {
  question_id: string;
  selected_index: number;
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
    .select(
      "id, name, join_code, host_name, quiz_id, starts_at, ends_at, closed_at, quizzes(title)",
    )
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

  const top5: SessionLiveTopRow[] = completed.slice(0, 5).map(toTopRow);
  const standings: SessionLiveTopRow[] = completed.map(toTopRow);

  const quizRel = Array.isArray(header.quizzes) ? header.quizzes[0] : header.quizzes;
  const nowMs = Date.now();

  // Per-question distribution. We pull the quiz's active questions and any
  // answers for attempts belonging to this session, then aggregate counts in
  // memory. Capped at 500 attempts above so this stays bounded.
  const { data: questionsData, error: questionsError } = await supabase
    .from("questions")
    .select("id, prompt, options, correct_index, position")
    .eq("quiz_id", header.quiz_id)
    .eq("is_active", true)
    .order("position", { ascending: true, nullsFirst: false });
  if (questionsError) {
    throw new Error(`Failed to load questions: ${questionsError.message}`);
  }
  const questions = (questionsData as LiveQuestionRow[] | null) ?? [];

  const attemptIds = attempts.map((a) => a.id);
  let answers: LiveAnswerRow[] = [];
  if (attemptIds.length > 0) {
    const { data: answersData, error: answersError } = await supabase
      .from("answers")
      .select("question_id, selected_index")
      .in("attempt_id", attemptIds);
    if (answersError) {
      throw new Error(`Failed to load answers: ${answersError.message}`);
    }
    answers = (answersData as LiveAnswerRow[] | null) ?? [];
  }

  const countsByQuestion = new Map<string, Map<number, number>>();
  for (const ans of answers) {
    let bucket = countsByQuestion.get(ans.question_id);
    if (!bucket) {
      bucket = new Map<number, number>();
      countsByQuestion.set(ans.question_id, bucket);
    }
    bucket.set(ans.selected_index, (bucket.get(ans.selected_index) ?? 0) + 1);
  }

  const perQuestion: SessionLiveQuestionStat[] = questions.map((q) => {
    const optionsArr = Array.isArray(q.options)
      ? (q.options as unknown[]).map((o) => String(o))
      : [];
    const bucket = countsByQuestion.get(q.id);
    const optionCounts = optionsArr.map(
      (_, idx) => bucket?.get(idx) ?? 0,
    );
    const totalAnswers = optionCounts.reduce((acc, v) => acc + v, 0);
    return {
      questionId: q.id,
      prompt: q.prompt,
      options: optionsArr,
      correctIndex: q.correct_index,
      totalAnswers,
      optionCounts,
    };
  });

  return {
    sessionId: header.id,
    name: header.name,
    joinCode: header.join_code,
    hostName: header.host_name,
    startsAt: header.starts_at,
    endsAt: header.ends_at,
    closedAt: header.closed_at,
    quizTitle: quizRel?.title ?? "(unknown quiz)",
    totalQuestions: questions.length,
    isActiveNow: isActiveNow(header.starts_at, header.ends_at, header.closed_at, nowMs),
    joined: uniqueUsers.size,
    scanned,
    submitted,
    lastActivityAt: lastActivityMs > 0 ? new Date(lastActivityMs).toISOString() : null,
    top5,
    standings,
    perQuestion,
  };
}

function toTopRow(a: LiveAttemptRow): SessionLiveTopRow {
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
}
