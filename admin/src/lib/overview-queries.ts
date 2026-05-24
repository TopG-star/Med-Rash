import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

/* ============================================================================
 * Overview KPIs — small aggregates the Dashboard and Intelligence pages need
 * up top. Kept narrow on purpose; deep slices live in reports-queries.ts.
 * ========================================================================== */

export type OverviewKpis = {
  totalUsers: number;
  completedAttempts: number;
  averageScorePercent: number | null; // 0..100, or null when no completed attempts
  activeQuizzes: number;
};

type AttemptScoreRow = {
  score: number | string | null;
  total_questions: number | string | null;
};

export async function getOverviewKpis(
  options: { createdBy?: string | null } = {},
): Promise<OverviewKpis> {
  const createdBy = options.createdBy ?? null;
  const supabase = getAdminSupabaseClient();
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  // ---- Host scoping --------------------------------------------------------
  // When a Host (createdBy != null) is viewing, we restrict all aggregates to
  // sessions they created. Quizzes are restricted to those they authored.
  // "Total Users" becomes "distinct users that participated in your sessions".
  if (createdBy) {
    // Pre-resolve owned session IDs. Empty list short-circuits to zeros so a
    // fresh Host with no sessions sees a sane KPI strip instead of a 500.
    const { data: sessRows, error: sessErr } = await supabase
      .from("sessions")
      .select("id")
      .eq("created_by", createdBy);
    if (sessErr) {
      throw new Error(
        `Failed to load host session ids: ${sessErr.message}`,
      );
    }
    const sessionIds = ((sessRows as { id: string }[] | null) ?? []).map(
      (r) => r.id,
    );

    const activeQuizzesPromise = supabase
      .from("quizzes")
      .select("id", { head: true, count: "exact" })
      .eq("is_active", true)
      .eq("created_by", createdBy);

    if (sessionIds.length === 0) {
      const activeQuizzesResult = await activeQuizzesPromise;
      if (activeQuizzesResult.error) {
        throw new Error(
          `Failed to load active quiz count: ${activeQuizzesResult.error.message}`,
        );
      }
      return {
        totalUsers: 0,
        completedAttempts: 0,
        averageScorePercent: null,
        activeQuizzes: activeQuizzesResult.count ?? 0,
      };
    }

    const completedCountPromise = supabase
      .from("attempts")
      .select("id", { head: true, count: "exact" })
      .not("completed_at", "is", null)
      .in("session_id", sessionIds);

    const distinctUsersPromise = supabase
      .from("attempts")
      .select("user_id")
      .in("session_id", sessionIds)
      .limit(50000);

    const scopedScoresPromise = supabase
      .from("attempts")
      .select("score, total_questions")
      .not("completed_at", "is", null)
      .gte("completed_at", since)
      .in("session_id", sessionIds)
      .limit(5000);

    const [
      completedResult,
      activeQuizzesResult,
      distinctUsersResult,
      scoresResult,
    ] = await Promise.all([
      completedCountPromise,
      activeQuizzesPromise,
      distinctUsersPromise,
      scopedScoresPromise,
    ]);

    if (completedResult.error) {
      throw new Error(
        `Failed to load completed attempt count: ${completedResult.error.message}`,
      );
    }
    if (activeQuizzesResult.error) {
      throw new Error(
        `Failed to load active quiz count: ${activeQuizzesResult.error.message}`,
      );
    }
    if (distinctUsersResult.error) {
      throw new Error(
        `Failed to load distinct host users: ${distinctUsersResult.error.message}`,
      );
    }
    if (scoresResult.error) {
      throw new Error(
        `Failed to load attempt scores: ${scoresResult.error.message}`,
      );
    }

    const distinctUserIds = new Set<string>();
    for (const row of (distinctUsersResult.data as
      | Array<{ user_id: string | null }>
      | null) ?? []) {
      if (row.user_id) distinctUserIds.add(row.user_id);
    }

    const scopedRows = (scoresResult.data as AttemptScoreRow[] | null) ?? [];
    let scopedSum = 0;
    let scopedCount = 0;
    for (const row of scopedRows) {
      const total = Number(row.total_questions ?? 0);
      const score = Number(row.score ?? 0);
      if (total > 0) {
        scopedSum += (score / total) * 100;
        scopedCount += 1;
      }
    }
    const scopedAverage =
      scopedCount > 0
        ? Math.round((scopedSum / scopedCount) * 10) / 10
        : null;

    return {
      totalUsers: distinctUserIds.size,
      completedAttempts: completedResult.count ?? 0,
      averageScorePercent: scopedAverage,
      activeQuizzes: activeQuizzesResult.count ?? 0,
    };
  }

  // ---- Owner: workspace-wide aggregates -----------------------------------
  // count(distinct users) — cheap head:true count.
  const usersCountPromise = supabase
    .from("users")
    .select("id", { head: true, count: "exact" });

  // count(attempts where completed_at is not null)
  const completedCountPromise = supabase
    .from("attempts")
    .select("id", { head: true, count: "exact" })
    .not("completed_at", "is", null);

  // count(active quizzes)
  const activeQuizzesPromise = supabase
    .from("quizzes")
    .select("id", { head: true, count: "exact" })
    .eq("is_active", true);

  // Pull the (score, total_questions) pairs for completed attempts in the last
  // 30 days and average them client-side. Bounded at 5000 to keep the response
  // small; the average smooths regardless.
  const scoresPromise = supabase
    .from("attempts")
    .select("score, total_questions")
    .not("completed_at", "is", null)
    .gte("completed_at", since)
    .limit(5000);

  const [usersResult, completedResult, activeQuizzesResult, scoresResult] =
    await Promise.all([
      usersCountPromise,
      completedCountPromise,
      activeQuizzesPromise,
      scoresPromise,
    ]);

  if (usersResult.error) {
    throw new Error(`Failed to load user count: ${usersResult.error.message}`);
  }
  if (completedResult.error) {
    throw new Error(
      `Failed to load completed attempt count: ${completedResult.error.message}`,
    );
  }
  if (activeQuizzesResult.error) {
    throw new Error(
      `Failed to load active quiz count: ${activeQuizzesResult.error.message}`,
    );
  }
  if (scoresResult.error) {
    throw new Error(
      `Failed to load attempt scores: ${scoresResult.error.message}`,
    );
  }

  const rows = (scoresResult.data as AttemptScoreRow[] | null) ?? [];
  let percentSum = 0;
  let percentCount = 0;
  for (const row of rows) {
    const total = Number(row.total_questions ?? 0);
    const score = Number(row.score ?? 0);
    if (total > 0) {
      percentSum += (score / total) * 100;
      percentCount += 1;
    }
  }
  const averageScorePercent =
    percentCount > 0 ? Math.round((percentSum / percentCount) * 10) / 10 : null;

  return {
    totalUsers: usersResult.count ?? 0,
    completedAttempts: completedResult.count ?? 0,
    averageScorePercent,
    activeQuizzes: activeQuizzesResult.count ?? 0,
  };
}
