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
