import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

/* ============================================================================
 * Shared types
 * ========================================================================== */

export type ReportFilters = {
  startsAt?: string | null; // ISO datetime lower bound (inclusive) on attempts.started_at
  endsAt?: string | null; // ISO datetime upper bound (inclusive)
  quizId?: string | null;
  sessionId?: string | null;
  facility?: string | null;
  specialty?: string | null;
};

/* ============================================================================
 * Intelligence: most-missed (knowledge gaps)
 * ========================================================================== */

export type MostMissedRow = {
  questionId: string;
  quizTitle: string;
  prompt: string;
  tags: string[];
  attemptsCount: number;
  incorrectCount: number;
  incorrectRate: number; // percent, 0..100
};

type MostMissedRpcRow = {
  question_id: string;
  quiz_title: string | null;
  prompt: string;
  tags: string[] | null;
  attempts_count: number | string;
  incorrect_count: number | string;
  incorrect_rate: number | string | null;
};

export async function getMostMissed(
  limit: number,
  filters: Pick<ReportFilters, "specialty" | "facility" | "sessionId"> = {},
  scope: { createdBy?: string | null } = {},
): Promise<MostMissedRow[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase.rpc("knowledge_gaps", {
    limit_count: limit,
    specialty_filter: filters.specialty ?? null,
    facility_filter: filters.facility ?? null,
    session_filter: filters.sessionId ?? null,
    created_by_filter: scope.createdBy ?? null,
  });
  if (error) {
    throw new Error(`Failed to load most-missed: ${error.message}`);
  }
  const rows = (data as MostMissedRpcRow[] | null) ?? [];
  return rows.map((r) => ({
    questionId: r.question_id,
    quizTitle: r.quiz_title ?? "",
    prompt: r.prompt,
    tags: r.tags ?? [],
    attemptsCount: Number(r.attempts_count),
    incorrectCount: Number(r.incorrect_count),
    incorrectRate: r.incorrect_rate === null ? 0 : Number(r.incorrect_rate),
  }));
}

/* ============================================================================
 * Intelligence: facility performance
 * ========================================================================== */

export type FacilityPerformanceRow = {
  facility: string;
  averageScore: number | null;
  completedAttempts: number;
  rankedParticipants: number;
  completionRate: number | null;
};

type FacilityPerformanceRpcRow = {
  facility: string | null;
  average_score: number | string | null;
  completed_attempts: number | string;
  ranked_participants: number | string;
  completion_rate: number | string | null;
};

export async function getFacilityPerformance(
  limit: number,
  scope: { createdBy?: string | null } = {},
): Promise<FacilityPerformanceRow[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase.rpc("facility_performance", {
    limit_count: limit,
    created_by_filter: scope.createdBy ?? null,
  });
  if (error) {
    throw new Error(`Failed to load facility performance: ${error.message}`);
  }
  const rows = (data as FacilityPerformanceRpcRow[] | null) ?? [];
  return rows.map((r) => ({
    facility: r.facility ?? "(unspecified)",
    averageScore: r.average_score === null ? null : Number(r.average_score),
    completedAttempts: Number(r.completed_attempts),
    rankedParticipants: Number(r.ranked_participants),
    completionRate:
      r.completion_rate === null ? null : Number(r.completion_rate),
  }));
}

/* ============================================================================
 * Intelligence: treatment perception trends
 * ========================================================================== */

export type TreatmentPerceptionRow = {
  clinicalArea: string | null;
  prompt: string;
  mostSelectedWrongOption: string;
  wrongSelectionCount: number;
  incorrectRate: number;
};

type TreatmentPerceptionRpcRow = {
  clinical_area: string | null;
  prompt: string;
  most_selected_wrong_option: string;
  wrong_selection_count: number | string;
  incorrect_rate: number | string | null;
};

export async function getTreatmentPerception(
  limit: number,
  scope: { createdBy?: string | null } = {},
): Promise<TreatmentPerceptionRow[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase.rpc("treatment_perception_trends", {
    limit_count: limit,
    created_by_filter: scope.createdBy ?? null,
  });
  if (error) {
    throw new Error(`Failed to load treatment perception: ${error.message}`);
  }
  const rows = (data as TreatmentPerceptionRpcRow[] | null) ?? [];
  return rows.map((r) => ({
    clinicalArea: r.clinical_area,
    prompt: r.prompt,
    mostSelectedWrongOption: r.most_selected_wrong_option,
    wrongSelectionCount: Number(r.wrong_selection_count),
    incorrectRate: r.incorrect_rate === null ? 0 : Number(r.incorrect_rate),
  }));
}

/* ============================================================================
 * Bulk export: attempts (one row per attempt with user + quiz + session)
 * ========================================================================== */

export type AttemptExportRow = {
  attemptId: string;
  startedAt: string;
  completedAt: string | null;
  mode: string;
  origin: string;
  score: number;
  totalQuestions: number;
  timeTakenMs: number;
  seasonKey: string;
  userId: string;
  userFullName: string;
  userNickname: string;
  userFacility: string;
  userSpecialty: string;
  userProfession: string | null;
  quizId: string;
  quizSlug: string;
  quizTitle: string;
  sessionId: string | null;
  sessionName: string | null;
  sessionJoinCode: string | null;
};

type AttemptExportRpcRow = {
  id: string;
  started_at: string;
  completed_at: string | null;
  mode: string;
  origin: string;
  score: number;
  total_questions: number;
  time_taken_ms: number;
  season_key: string;
  user_id: string;
  quiz_id: string;
  session_id: string | null;
  users:
    | {
        full_name: string | null;
        nickname: string | null;
        facility: string | null;
        specialty: string | null;
        profession: string | null;
      }
    | Array<{
        full_name: string | null;
        nickname: string | null;
        facility: string | null;
        specialty: string | null;
        profession: string | null;
      }>
    | null;
  quizzes:
    | { slug: string | null; title: string | null }
    | Array<{ slug: string | null; title: string | null }>
    | null;
  sessions:
    | { name: string | null; join_code: string | null }
    | Array<{ name: string | null; join_code: string | null }>
    | null;
};

function pickRel<T>(value: T | T[] | null): T | null {
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) return value[0] ?? null;
  return value;
}

/**
 * Pre-fetch the session IDs created by a given admin user (Host). Returned
 * list is used to client-side filter attempts/answers exports via `.in()`.
 * Returns an empty list when the user has not created any sessions yet.
 */
async function getSessionIdsCreatedBy(userId: string): Promise<string[]> {
  const supabase = getAdminSupabaseClient();
  const { data, error } = await supabase
    .from("sessions")
    .select("id")
    .eq("created_by", userId);
  if (error) {
    throw new Error(
      `Failed to load host session ids for '${userId}': ${error.message}`,
    );
  }
  return ((data as { id: string }[] | null) ?? []).map((r) => r.id);
}

/**
 * Minimal contract for the Supabase query-builder methods we chain in this
 * file. Kept narrow so we don't depend on the generated table-typings (the
 * admin client is created without them).
 */
type FilterableQuery<TSelf> = {
  gte: (column: string, value: string) => TSelf;
  lte: (column: string, value: string) => TSelf;
  eq: (column: string, value: string) => TSelf;
};

/**
 * Apply common date / quiz / session filters to a Supabase attempts-style
 * query. Kept as a small helper so both attempts + answers exports share
 * guardrails.
 */
function applyAttemptFilters<TQuery extends FilterableQuery<TQuery>>(
  query: TQuery,
  filters: ReportFilters,
  attemptTablePrefix = "",
): TQuery {
  let next = query;
  const startedCol = `${attemptTablePrefix}started_at`;
  const quizCol = `${attemptTablePrefix}quiz_id`;
  const sessionCol = `${attemptTablePrefix}session_id`;
  if (filters.startsAt) next = next.gte(startedCol, filters.startsAt);
  if (filters.endsAt) next = next.lte(startedCol, filters.endsAt);
  if (filters.quizId) next = next.eq(quizCol, filters.quizId);
  if (filters.sessionId) next = next.eq(sessionCol, filters.sessionId);
  return next;
}

export async function getAttemptsExport(
  filters: ReportFilters,
  limit = 5000,
  scope: { createdBy?: string | null } = {},
): Promise<AttemptExportRow[]> {
  const supabase = getAdminSupabaseClient();

  // Host scoping: pre-resolve owned session IDs. Empty list short-circuits to
  // zero rows so a Host never sees other teammates' attempts.
  let allowedSessionIds: string[] | null = null;
  if (scope.createdBy) {
    allowedSessionIds = await getSessionIdsCreatedBy(scope.createdBy);
    if (allowedSessionIds.length === 0) return [];
  }

  let query = supabase
    .from("attempts")
    .select(
      "id, started_at, completed_at, mode, origin, score, total_questions, time_taken_ms, season_key, user_id, quiz_id, session_id, users(full_name, nickname, facility, specialty, profession), quizzes(slug, title), sessions(name, join_code)",
    )
    .order("started_at", { ascending: false })
    .limit(limit);

  query = applyAttemptFilters(query, filters);
  if (allowedSessionIds) {
    query = query.in("session_id", allowedSessionIds);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(`Failed to load attempts export: ${error.message}`);
  }
  const rows = (data as AttemptExportRpcRow[] | null) ?? [];
  return rows.map((r) => {
    const user = pickRel(r.users);
    const quiz = pickRel(r.quizzes);
    const session = pickRel(r.sessions);
    return {
      attemptId: r.id,
      startedAt: r.started_at,
      completedAt: r.completed_at,
      mode: r.mode,
      origin: r.origin,
      score: r.score,
      totalQuestions: r.total_questions,
      timeTakenMs: r.time_taken_ms,
      seasonKey: r.season_key,
      userId: r.user_id,
      userFullName: user?.full_name ?? "",
      userNickname: user?.nickname ?? "",
      userFacility: user?.facility ?? "",
      userSpecialty: user?.specialty ?? "",
      userProfession: user?.profession ?? null,
      quizId: r.quiz_id,
      quizSlug: quiz?.slug ?? "",
      quizTitle: quiz?.title ?? "",
      sessionId: r.session_id,
      sessionName: session?.name ?? null,
      sessionJoinCode: session?.join_code ?? null,
    };
  });
}

/* ============================================================================
 * Bulk export: answers (one row per answered question)
 * ========================================================================== */

export type AnswerExportRow = {
  answerId: string;
  answeredAt: string;
  attemptId: string;
  attemptStartedAt: string;
  attemptCompletedAt: string | null;
  attemptMode: string;
  attemptOrigin: string;
  seasonKey: string;
  userId: string;
  userFullName: string;
  userNickname: string;
  userFacility: string;
  userSpecialty: string;
  quizId: string;
  quizSlug: string;
  quizTitle: string;
  sessionId: string | null;
  sessionName: string | null;
  sessionJoinCode: string | null;
  questionId: string;
  prompt: string;
  clinicalArea: string | null;
  selectedIndex: number;
  selectedOptionText: string;
  correctIndex: number;
  isCorrect: boolean;
  responseTimeMs: number;
};

type AnswerExportRpcRow = {
  id: string;
  answered_at: string;
  selected_index: number;
  selected_option_text: string;
  is_correct: boolean;
  response_time_ms: number;
  attempt_id: string;
  question_id: string;
  attempts:
    | {
        started_at: string | null;
        completed_at: string | null;
        mode: string | null;
        origin: string | null;
        season_key: string | null;
        user_id: string | null;
        quiz_id: string | null;
        session_id: string | null;
        users:
          | {
              full_name: string | null;
              nickname: string | null;
              facility: string | null;
              specialty: string | null;
            }
          | Array<{
              full_name: string | null;
              nickname: string | null;
              facility: string | null;
              specialty: string | null;
            }>
          | null;
        quizzes:
          | { slug: string | null; title: string | null }
          | Array<{ slug: string | null; title: string | null }>
          | null;
        sessions:
          | { name: string | null; join_code: string | null }
          | Array<{ name: string | null; join_code: string | null }>
          | null;
      }
    | Array<{
        started_at: string | null;
        completed_at: string | null;
        mode: string | null;
        origin: string | null;
        season_key: string | null;
        user_id: string | null;
        quiz_id: string | null;
        session_id: string | null;
        users: unknown;
        quizzes: unknown;
        sessions: unknown;
      }>
    | null;
  questions:
    | {
        prompt: string | null;
        clinical_area: string | null;
        correct_index: number | null;
      }
    | Array<{
        prompt: string | null;
        clinical_area: string | null;
        correct_index: number | null;
      }>
    | null;
};

export async function getAnswersExport(
  filters: ReportFilters,
  limit = 10000,
  scope: { createdBy?: string | null } = {},
): Promise<AnswerExportRow[]> {
  const supabase = getAdminSupabaseClient();

  let allowedSessionIds: string[] | null = null;
  if (scope.createdBy) {
    allowedSessionIds = await getSessionIdsCreatedBy(scope.createdBy);
    if (allowedSessionIds.length === 0) return [];
  }

  let query = supabase
    .from("answers")
    .select(
      "id, answered_at, selected_index, selected_option_text, is_correct, response_time_ms, attempt_id, question_id, attempts!inner(started_at, completed_at, mode, origin, season_key, user_id, quiz_id, session_id, users(full_name, nickname, facility, specialty), quizzes(slug, title), sessions(name, join_code)), questions(prompt, clinical_area, correct_index)",
    )
    .order("answered_at", { ascending: false })
    .limit(limit);

  query = applyAttemptFilters(query, filters, "attempts.");
  if (allowedSessionIds) {
    query = query.in("attempts.session_id", allowedSessionIds);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(`Failed to load answers export: ${error.message}`);
  }
  const rows = (data as AnswerExportRpcRow[] | null) ?? [];
  return rows.map((r) => {
    const attempt = pickRel(r.attempts) as {
      started_at: string | null;
      completed_at: string | null;
      mode: string | null;
      origin: string | null;
      season_key: string | null;
      user_id: string | null;
      quiz_id: string | null;
      session_id: string | null;
      users: unknown;
      quizzes: unknown;
      sessions: unknown;
    } | null;
    const user = pickRel(
      attempt?.users as
        | {
            full_name: string | null;
            nickname: string | null;
            facility: string | null;
            specialty: string | null;
          }
        | Array<{
            full_name: string | null;
            nickname: string | null;
            facility: string | null;
            specialty: string | null;
          }>
        | null,
    );
    const quiz = pickRel(
      attempt?.quizzes as
        | { slug: string | null; title: string | null }
        | Array<{ slug: string | null; title: string | null }>
        | null,
    );
    const session = pickRel(
      attempt?.sessions as
        | { name: string | null; join_code: string | null }
        | Array<{ name: string | null; join_code: string | null }>
        | null,
    );
    const question = pickRel(r.questions);
    return {
      answerId: r.id,
      answeredAt: r.answered_at,
      attemptId: r.attempt_id,
      attemptStartedAt: attempt?.started_at ?? "",
      attemptCompletedAt: attempt?.completed_at ?? null,
      attemptMode: attempt?.mode ?? "",
      attemptOrigin: attempt?.origin ?? "",
      seasonKey: attempt?.season_key ?? "",
      userId: attempt?.user_id ?? "",
      userFullName: user?.full_name ?? "",
      userNickname: user?.nickname ?? "",
      userFacility: user?.facility ?? "",
      userSpecialty: user?.specialty ?? "",
      quizId: attempt?.quiz_id ?? "",
      quizSlug: quiz?.slug ?? "",
      quizTitle: quiz?.title ?? "",
      sessionId: attempt?.session_id ?? null,
      sessionName: session?.name ?? null,
      sessionJoinCode: session?.join_code ?? null,
      questionId: r.question_id,
      prompt: question?.prompt ?? "",
      clinicalArea: question?.clinical_area ?? null,
      selectedIndex: r.selected_index,
      selectedOptionText: r.selected_option_text,
      correctIndex: question?.correct_index ?? -1,
      isCorrect: r.is_correct,
      responseTimeMs: r.response_time_ms,
    };
  });
}
