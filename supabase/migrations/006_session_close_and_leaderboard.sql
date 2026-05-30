-- Migration 006 — Session-scoped leaderboard surface.
--
-- Adds an explicit `closed_at` column so a host/admin can end a session
-- intentionally (preferred), and exposes two read RPCs the participant
-- app polls while a session is live:
--   * app.session_leaderboard(session, limit) — ranked rows for that session
--   * app.my_session_rank(session, user) — current user's row even when
--                                          they fell outside the top N
--   * app.session_is_live(session) — single source of truth for liveness
--
-- Ranking rule (locked, see chat decision D1):
--   1) score DESC
--   2) time_taken_ms ASC (faster wins ties only; doesn't penalise high scorers)
--   3) completed_at ASC (stable terminal tie-break)
--
-- Liveness rule (locked, decision D2): both an explicit `closed_at` override
-- AND an automatic `ends_at` safety net, fronted by app.session_is_live so
-- every surface agrees on the predicate without copy-pasting it.
--
-- Global ranked totals (app.ranked_attempt_totals_*) intentionally do NOT
-- filter by session_id, so the same ranked attempt that lands here also grows
-- the participant's all-time + monthly totals — that's the correctness
-- property the chat scenario calls out (User A: 10 + 5 = 15 globally, while
-- the session board shows the in-session 5).

alter table app.sessions
  add column if not exists closed_at timestamptz null;

comment on column app.sessions.closed_at is
  'Set by host/admin when the session is explicitly ended. '
  'NULL = session may still be live (subject to starts_at/ends_at). '
  'See app.session_is_live for the canonical liveness predicate.';

create or replace function app.session_is_live(
  target_session uuid,
  at_ts timestamptz default now()
)
returns boolean
language sql
stable
as $$
  select coalesce(
    (
      select
        s.closed_at is null
        and (s.starts_at is null or s.starts_at <= at_ts)
        and (s.ends_at   is null or at_ts        <= s.ends_at)
      from app.sessions s
      where s.id = target_session
    ),
    false
  );
$$;

create or replace function app.session_leaderboard(
  target_session uuid,
  limit_count integer default 50
)
returns table (
  rank_position bigint,
  user_id uuid,
  nickname text,
  session_score integer,
  time_taken_ms integer,
  completed_at timestamptz
)
language sql
stable
as $$
  with session_ranked as (
    select
      rank() over (
        order by a.score          desc,
                 a.time_taken_ms  asc,
                 a.completed_at   asc
      ) as rank_position,
      a.user_id,
      u.nickname,
      a.score          as session_score,
      a.time_taken_ms,
      a.completed_at
    from app.attempts a
    join app.users u on u.id = a.user_id
    where a.session_id  = target_session
      and a.mode        = 'ranked'
      and a.completed_at is not null
  )
  select rank_position, user_id, nickname,
         session_score, time_taken_ms, completed_at
  from session_ranked
  order by rank_position, nickname
  limit greatest(limit_count, 1);
$$;

create or replace function app.my_session_rank(
  target_session uuid,
  target_user uuid
)
returns table (
  rank_position bigint,
  user_id uuid,
  nickname text,
  session_score integer,
  time_taken_ms integer,
  completed_at timestamptz
)
language sql
stable
as $$
  with session_ranked as (
    select
      rank() over (
        order by a.score          desc,
                 a.time_taken_ms  asc,
                 a.completed_at   asc
      ) as rank_position,
      a.user_id,
      u.nickname,
      a.score          as session_score,
      a.time_taken_ms,
      a.completed_at
    from app.attempts a
    join app.users u on u.id = a.user_id
    where a.session_id  = target_session
      and a.mode        = 'ranked'
      and a.completed_at is not null
  )
  select rank_position, user_id, nickname,
         session_score, time_taken_ms, completed_at
  from session_ranked
  where user_id = target_user;
$$;
