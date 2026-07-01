-- Phase 2 (P2.1) — server-authoritative gamification: XP, levels, streak,
-- daily goal, and badges.
--
-- Why this exists:
--   Before this migration the retention loop (streak / career points / medals)
--   lived entirely in the Flutter client's SharedPreferences. That means it
--   reset on device handover, never synced across devices, and the backend
--   could not drive re-engagement (streak-about-to-die reminders, KPI roll-ups)
--   or report on it. This migration moves progression to the server so the
--   client renders authoritative values returned by `attempt-submit`.
--
-- Scope (per product decision): XP + levels + streak + daily goal + badges.
--   Deliberately NOT hearts/lives and NOT leagues — those change ranked-mode
--   scope and add the largest new surface; revisit post-pilot.
--
-- Model:
--   * app.user_progress — ONE row per user. xp, current/best streak,
--     last_active_date (Africa/Accra calendar day, matching season_key logic
--     in migration 004), daily_goal.
--   * app.badges — admin-authored catalog (public read).
--   * app.user_badges — awards, one row per (user, badge).
--   * app.level_for_xp(xp) — pure curve: level N needs 250*(N-1) cumulative XP.
--   * app.record_attempt_progress(...) — SECURITY DEFINER RPC called once per
--     freshly-inserted attempt by the Netlify gate. Accrues XP, advances the
--     streak on the Accra calendar, awards eligible badges, and returns the
--     new snapshot (incl. leveled_up + newly_earned) for the client.
--
-- Non-blocking contract: attempt-submit calls the RPC AFTER the attempt row is
-- committed and treats any RPC failure as a logged warning — a progression
-- hiccup must never fail an attempt submission.

begin;

-- ============================================================================
-- 1. Tables
-- ============================================================================
create table if not exists app.user_progress (
  user_id           uuid primary key references app.users(id) on delete cascade,
  xp                integer     not null default 0 check (xp >= 0),
  current_streak    integer     not null default 0 check (current_streak >= 0),
  best_streak       integer     not null default 0 check (best_streak >= 0),
  last_active_date  date,
  daily_goal        integer     not null default 5 check (daily_goal between 1 and 100),
  updated_at        timestamptz not null default now()
);

comment on table app.user_progress is
  'Server-authoritative gamification state (XP, streak, daily goal) — one row per user.';
comment on column app.user_progress.last_active_date is
  'Africa/Accra calendar day of the most recent completed attempt. Streak math buckets on this.';

create table if not exists app.badges (
  code         text primary key,
  title        text not null,
  description  text not null,
  tier         text not null default 'bronze' check (tier in ('bronze','silver','gold','mint')),
  icon         text not null default 'military_tech',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

comment on table app.badges is 'Admin-authored badge catalog. Public read; service_role write.';

create table if not exists app.user_badges (
  user_id    uuid not null references app.users(id) on delete cascade,
  badge_code text not null references app.badges(code) on delete cascade,
  earned_at  timestamptz not null default now(),
  primary key (user_id, badge_code)
);

create index if not exists user_badges_user_idx on app.user_badges (user_id);

-- ============================================================================
-- 2. XP → level curve  (level N requires 250*(N-1) cumulative XP)
-- ============================================================================
create or replace function app.level_for_xp(p_xp integer)
returns integer
language sql
immutable
as $$
  select greatest(1, floor(coalesce(p_xp, 0) / 250.0)::int + 1);
$$;

comment on function app.level_for_xp(integer) is
  'Pure XP→level curve. Level 1 = 0-249 XP, level 2 = 250-499, etc. Tune the 250 divisor as the economy matures.';

-- ============================================================================
-- 3. Row-Level Security
-- ============================================================================
alter table app.user_progress enable row level security;
alter table app.badges        enable row level security;
alter table app.user_badges   enable row level security;

drop policy if exists user_progress_service_role_all on app.user_progress;
create policy user_progress_service_role_all on app.user_progress
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists user_badges_service_role_all on app.user_badges;
create policy user_badges_service_role_all on app.user_badges
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists badges_public_select on app.badges;
create policy badges_public_select on app.badges
  for select using (is_active = true or auth.role() = 'service_role');

drop policy if exists badges_service_role_all on app.badges;
create policy badges_service_role_all on app.badges
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- A claimed (logged-in) participant can read their own progression + awards
-- directly via RLS (mirrors the users_claimed_self_select pattern in 001).
drop policy if exists user_progress_claimed_self_select on app.user_progress;
create policy user_progress_claimed_self_select on app.user_progress
  for select using (
    exists (select 1 from app.users u
            where u.id = user_progress.user_id and u.claimed_auth_user_id = auth.uid())
  );

drop policy if exists user_badges_claimed_self_select on app.user_badges;
create policy user_badges_claimed_self_select on app.user_badges
  for select using (
    exists (select 1 from app.users u
            where u.id = user_badges.user_id and u.claimed_auth_user_id = auth.uid())
  );

-- ============================================================================
-- 4. Progression RPC (SECURITY DEFINER — called by the Netlify gate)
-- ============================================================================
create or replace function app.record_attempt_progress(
  p_user_id   uuid,
  p_score     integer,
  p_total     integer,
  p_mode      app.attempt_mode,
  p_completed timestamptz
)
returns table (
  xp             integer,
  level          integer,
  current_streak integer,
  best_streak    integer,
  xp_gained      integer,
  leveled_up     boolean,
  newly_earned   text[]
)
language plpgsql
security definer
set search_path = app
as $$
declare
  v_today       date := (p_completed at time zone 'Africa/Accra')::date;
  v_gain        integer;
  v_prev_xp     integer;
  v_prev_level  integer;
  v_new         app.user_progress%rowtype;
  v_new_level   integer;
  v_earned      text[] := '{}';
begin
  -- XP economy: 10 per correct answer + 20 ranked-completion bonus. Tune freely.
  v_gain := greatest(0, coalesce(p_score, 0)) * 10
            + (case when p_mode = 'ranked' then 20 else 0 end);

  insert into app.user_progress(user_id) values (p_user_id)
    on conflict (user_id) do nothing;

  -- Lock the row for a consistent read-modify-write.
  select xp into v_prev_xp from app.user_progress where user_id = p_user_id for update;
  v_prev_level := app.level_for_xp(v_prev_xp);

  update app.user_progress p set
    xp = p.xp + v_gain,
    current_streak = case
      when p.last_active_date = v_today       then greatest(p.current_streak, 1)
      when p.last_active_date = v_today - 1    then p.current_streak + 1
      else 1
    end,
    best_streak = greatest(
      p.best_streak,
      case
        when p.last_active_date = v_today - 1 then p.current_streak + 1
        when p.last_active_date = v_today     then greatest(p.current_streak, 1)
        else 1
      end
    ),
    last_active_date = v_today,
    updated_at = now()
  where p.user_id = p_user_id
  returning * into v_new;

  v_new_level := app.level_for_xp(v_new.xp);

  -- ---- Badge awards (extend as the catalog grows) ----
  -- first_win: any ranked attempt earns it once.
  if p_mode = 'ranked'
     and not exists (select 1 from app.user_badges
                     where user_id = p_user_id and badge_code = 'first_win') then
    insert into app.user_badges(user_id, badge_code) values (p_user_id, 'first_win')
      on conflict do nothing;
    v_earned := array_append(v_earned, 'first_win');
  end if;

  -- streak_3: three-day streak.
  if v_new.current_streak >= 3
     and not exists (select 1 from app.user_badges
                     where user_id = p_user_id and badge_code = 'streak_3') then
    insert into app.user_badges(user_id, badge_code) values (p_user_id, 'streak_3')
      on conflict do nothing;
    v_earned := array_append(v_earned, 'streak_3');
  end if;

  -- nutrition_ace-style perfect-score badge is quiz-specific; award generically
  -- on any perfect ranked score for now (rename/retune when catalog firms up).
  if p_mode = 'ranked' and p_total > 0 and p_score = p_total
     and not exists (select 1 from app.user_badges
                     where user_id = p_user_id and badge_code = 'nutrition_ace') then
    insert into app.user_badges(user_id, badge_code) values (p_user_id, 'nutrition_ace')
      on conflict do nothing;
    v_earned := array_append(v_earned, 'nutrition_ace');
  end if;

  return query
    select v_new.xp, v_new_level, v_new.current_streak, v_new.best_streak,
           v_gain, (v_new_level > v_prev_level), v_earned;
end;
$$;

revoke all on function
  app.record_attempt_progress(uuid, integer, integer, app.attempt_mode, timestamptz)
  from public;

comment on function app.record_attempt_progress(uuid, integer, integer, app.attempt_mode, timestamptz) is
  'Accrues XP + streak + badges for one completed attempt (Accra calendar). Called by the Netlify attempt-submit gate AFTER the attempt row is committed; non-blocking.';

-- ============================================================================
-- 5. Seed the pilot badge catalog (matches the v2 Badges screen)
-- ============================================================================
insert into app.badges (code, title, description, tier, icon) values
  ('first_win',     'First Win',     'Win your first ranked attempt.',        'bronze', 'bolt'),
  ('streak_3',      'Streak x3',     'Three days of quizzes in a row.',        'silver', 'local_fire_department'),
  ('nutrition_ace', 'Perfect Score', 'Score 100% on a ranked quiz.',           'mint',   'water_drop'),
  ('top_10',        'Top 10',        'Land in the monthly Top 10.',            'gold',   'emoji_events'),
  ('cme_25',        'CME 25',        'Complete 25 CME questions.',             'bronze', 'school'),
  ('legend',        'Legend',        'Reach #1 on the all-time board.',        'gold',   'workspace_premium')
on conflict (code) do nothing;

-- PostgREST schema reload so the new RPC + tables are visible to the API layer
-- immediately (same trailer used by migrations 007-010).
notify pgrst, 'reload schema';

commit;
