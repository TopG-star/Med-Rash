-- Phase 1 (P1.5 + P1.4a) — soft-delete + right-to-erasure on app.users,
-- plus a daily aggregate RPC for the KPI digest.
--
-- Erasure model (per product call):
--   * `deleted_at`  — generic soft-delete timestamp. Set when an account is
--     decommissioned for any reason (admin removal, account cleanup,
--     erasure request). Nullable; null means active.
--   * `is_erased` + `erased_at` — PII has been scrubbed pursuant to a
--     right-to-erasure (GDPR / similar) request. `is_erased = true` is
--     the durable signal used by public ranking views to exclude the
--     row. `erased_at` records when it happened.
--
-- Why both: a soft-deleted account that has NOT been erased still carries
-- PII (e.g. for legal hold or merger investigation). An erased account
-- carries no PII. Almost every erasure also soft-deletes; the converse
-- is not true.
--
-- Scrubbed fields (per product spec): full_name, nickname, facility,
-- specialty, profession, email, claimed_auth_user_id, metadata. The
-- internal `id` (UUID) is preserved so historical attempts/answers stay
-- joinable for de-identified analytics. user_devices rows are deleted
-- outright (device install IDs are identifiers).
--
-- Public ranking views (`ranked_attempt_totals_*`) are refreshed below
-- to filter `where u.is_erased = false`. Admin analytics functions
-- (`knowledge_gaps`, `facility_performance`) keep the row because the
-- joined PII fields are null after erasure — the data still aggregates,
-- the human just disappears.
--
-- NOT NULL relaxation: `full_name`, `nickname`, `facility`, `specialty`
-- are dropped to NULLABLE so the erasure UPDATE can null them. The
-- unique index on `lower(nickname)` already allows multiple nulls
-- (Postgres default for unique indexes); the index on `lower(email)`
-- was already partial (`where email is not null`).

begin;

-- ============================================================================
-- 1. Soft-delete / erasure columns + relaxed NOT NULLs
-- ============================================================================

alter table app.users
  add column if not exists deleted_at  timestamptz,
  add column if not exists is_erased   boolean      not null default false,
  add column if not exists erased_at   timestamptz;

alter table app.users alter column full_name drop not null;
alter table app.users alter column nickname  drop not null;
alter table app.users alter column facility  drop not null;
alter table app.users alter column specialty drop not null;

create index if not exists users_active_idx
  on app.users (id)
  where deleted_at is null and is_erased = false;

create index if not exists users_erased_idx
  on app.users (erased_at desc)
  where is_erased = true;

-- ============================================================================
-- 2. Public ranking views — exclude erased users
-- ============================================================================
-- `create or replace view` keeps the security_invoker option set in
-- migration 014, but we re-assert it after each replace to be defensive.

create or replace view app.ranked_attempt_totals_all_time as
select
  a.user_id,
  u.nickname,
  sum(a.score)::bigint as total_score,
  count(*)::bigint as ranked_attempts,
  max(a.completed_at) as last_ranked_at
from app.attempts a
join app.users u on u.id = a.user_id
where a.mode = 'ranked'
  and a.completed_at is not null
  and u.is_erased = false
group by a.user_id, u.nickname;

alter view app.ranked_attempt_totals_all_time set (security_invoker = true);

create or replace view app.ranked_attempt_totals_monthly as
select
  a.season_key,
  a.user_id,
  u.nickname,
  sum(a.score)::bigint as total_score,
  count(*)::bigint as ranked_attempts,
  max(a.completed_at) as last_ranked_at
from app.attempts a
join app.users u on u.id = a.user_id
where a.mode = 'ranked'
  and a.completed_at is not null
  and u.is_erased = false
group by a.season_key, a.user_id, u.nickname;

alter view app.ranked_attempt_totals_monthly set (security_invoker = true);

-- ============================================================================
-- 3. app.erase_user RPC
-- ============================================================================
-- security_definer so a service-role caller can scrub and write the
-- admin_audit row in one transaction. Caller MUST be service-role; we
-- enforce by revoking from public + granting only to service_role.
--
-- Audit row is written only when `p_actor_user_id` is supplied AND
-- references a real auth.users row (the table's actor_user_id FK is
-- NOT NULL with on delete restrict). Background/system-triggered
-- erasures pass null and skip the audit row — the operator records the
-- justification in the ticket system, not the DB.

create or replace function app.erase_user(
  p_user_id        uuid,
  p_actor_user_id  uuid default null
)
returns void
language plpgsql
security definer
set search_path = app, public
as $$
declare
  v_now timestamptz := now();
begin
  if not exists (select 1 from app.users where id = p_user_id) then
    raise exception 'user not found: %', p_user_id using errcode = 'P0002';
  end if;

  update app.users
  set
    deleted_at = coalesce(deleted_at, v_now),
    is_erased = true,
    erased_at = coalesce(erased_at, v_now),
    full_name = null,
    nickname = null,
    facility = null,
    specialty = null,
    profession = null,
    email = null,
    claimed_auth_user_id = null,
    metadata = '{}'::jsonb,
    updated_at = v_now
  where id = p_user_id;

  delete from app.user_devices where user_id = p_user_id;

  if p_actor_user_id is not null then
    insert into app.admin_audit (
      actor_user_id,
      actor_role,
      action,
      target_type,
      target_id,
      metadata
    )
    values (
      p_actor_user_id,
      'superadmin',
      'user_erased',
      'app.users',
      p_user_id::text,
      jsonb_build_object('erased_at', v_now)
    );
  end if;
end;
$$;

revoke all on function app.erase_user(uuid, uuid) from public;
grant execute on function app.erase_user(uuid, uuid) to service_role;

-- ============================================================================
-- 4. app.session_kpis_for_date — daily aggregate for the KPI digest
-- ============================================================================
-- One row per session that had ANY attempt activity on the given UTC date.
-- Drives the manager-facing morning digest (P1.4). Counts respect erasure:
-- erased users still contributed historical activity, so their attempts
-- still count toward join/completion totals (the row exists in
-- `app.attempts` with a foreign key to an anonymised user) but their
-- nickname does not appear anywhere.
--
-- The existing `app.session_kpis(uuid)` returns a single-session row; the
-- digest needs the whole day. We keep both functions side-by-side rather
-- than overload to avoid breaking the existing call sites.

create or replace function app.session_kpis_for_date(p_date date)
returns table (
  session_id          uuid,
  session_name        text,
  quiz_id             uuid,
  quiz_title          text,
  join_count          bigint,
  completed_count     bigint,
  completion_rate     numeric,
  average_score       numeric,
  median_time_seconds numeric
)
language sql
stable
as $$
  with day_attempts as (
    select a.*
    from app.attempts a
    where a.created_at >= p_date::timestamptz
      and a.created_at <  (p_date + 1)::timestamptz
  ),
  completed as (
    select * from day_attempts where completed_at is not null
  ),
  per_session as (
    select
      da.session_id,
      count(*)::bigint as join_count,
      count(c.id)::bigint as completed_count,
      case when count(*) = 0 then 0
           else round((count(c.id)::numeric / count(*)::numeric) * 100, 2)
      end as completion_rate,
      round(avg(c.score::numeric), 2) as average_score,
      round((percentile_cont(0.5) within group (order by c.time_taken_ms) / 1000.0)::numeric, 2)
        as median_time_seconds
    from day_attempts da
    left join completed c on c.id = da.id
    where da.session_id is not null
    group by da.session_id
  )
  select
    p.session_id,
    s.name        as session_name,
    s.quiz_id,
    qz.title      as quiz_title,
    p.join_count,
    p.completed_count,
    p.completion_rate,
    p.average_score,
    p.median_time_seconds
  from per_session p
  join app.sessions s on s.id = p.session_id
  left join app.quizzes qz on qz.id = s.quiz_id
  order by p.completed_count desc, p.join_count desc, s.name asc;
$$;

revoke all on function app.session_kpis_for_date(date) from public;
grant execute on function app.session_kpis_for_date(date) to service_role;

commit;
