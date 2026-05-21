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

export async function getOverviewKpis(): Promise<OverviewKpis> {
  const supabase = getAdminSupabaseClient();

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
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
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
