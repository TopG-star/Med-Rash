-- Slice A1 of docs/security-hardening-plan.md.
--
-- Persists OTP + per-identifier rate limiting in Postgres so the limits
-- survive Netlify cold-starts and horizontal scale. The previous in-memory
-- map in admin/src/app/login/actions.ts only protected one Node process at
-- a time; an attacker hitting different cold-started instances bypassed the
-- 5-wrong-in-15min cap.
--
-- Schema:
--   app.auth_rate_limit (
--     key            text primary key,     -- "scope:sha256(identifier)"
--     window_started_at timestamptz not null default now(),
--     attempt_count  int not null default 0,
--     locked_until   timestamptz null,     -- non-null while in lockout window
--     updated_at     timestamptz not null default now()
--   )
--
-- Standards: ISO 27002 §5.15, 5.17, 8.5 · OWASP ASVS V2.2 · NIST CSF PR.AA-3.

create table if not exists app.auth_rate_limit (
  key text primary key,
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists auth_rate_limit_locked_until_idx
  on app.auth_rate_limit (locked_until)
  where locked_until is not null;

alter table app.auth_rate_limit enable row level security;

drop policy if exists auth_rate_limit_service_role_all on app.auth_rate_limit;
create policy auth_rate_limit_service_role_all
  on app.auth_rate_limit
  as permissive
  for all
  to service_role
  using (true)
  with check (true);

-- enforce_rate_limit: atomic "check and increment" against a single row.
-- Returns one row describing the decision so callers do not need a second
-- round-trip. Concurrent callers serialize on the row lock obtained by the
-- upsert inside the function body.
--
-- Returned columns:
--   allowed              boolean  true when the request may proceed
--   attempts_remaining   integer  remaining attempts in the current window
--                                 (0 once the limit is hit; 0 while locked)
--   retry_after_seconds  integer  hint for Retry-After when allowed=false
--   locked_until         timestamptz nullable; non-null while in lockout
create or replace function app.enforce_rate_limit(
  p_key text,
  p_limit integer,
  p_window_seconds integer,
  p_lockout_seconds integer
)
returns table (
  allowed boolean,
  attempts_remaining integer,
  retry_after_seconds integer,
  locked_until timestamptz
)
language plpgsql
as $$
declare
  v_now timestamptz := now();
  v_row app.auth_rate_limit%rowtype;
  v_window_end timestamptz;
  v_lockout_end timestamptz;
begin
  if p_limit is null or p_limit <= 0 then
    raise exception 'enforce_rate_limit: p_limit must be > 0';
  end if;
  if p_window_seconds is null or p_window_seconds <= 0 then
    raise exception 'enforce_rate_limit: p_window_seconds must be > 0';
  end if;
  if p_lockout_seconds is null or p_lockout_seconds < 0 then
    raise exception 'enforce_rate_limit: p_lockout_seconds must be >= 0';
  end if;

  -- Take a row-level lock by upserting a placeholder if missing, then
  -- selecting FOR UPDATE. Doing it in two statements keeps the on-conflict
  -- path simple and avoids racing two callers into the same insert.
  insert into app.auth_rate_limit (key, window_started_at, attempt_count, updated_at)
  values (p_key, v_now, 0, v_now)
  on conflict (key) do nothing;

  select * into v_row
  from app.auth_rate_limit
  where key = p_key
  for update;

  -- Still in lockout window — deny without incrementing.
  if v_row.locked_until is not null and v_row.locked_until > v_now then
    return query select
      false,
      0,
      greatest(1, ceil(extract(epoch from (v_row.locked_until - v_now)))::integer),
      v_row.locked_until;
    return;
  end if;

  -- Lockout expired (or never set) and the rolling window expired -> reset.
  v_window_end := v_row.window_started_at + make_interval(secs => p_window_seconds);
  if v_window_end <= v_now then
    v_row.window_started_at := v_now;
    v_row.attempt_count := 0;
    v_row.locked_until := null;
    v_window_end := v_now + make_interval(secs => p_window_seconds);
  end if;

  v_row.attempt_count := v_row.attempt_count + 1;

  if v_row.attempt_count > p_limit then
    v_lockout_end := v_now + make_interval(secs => p_lockout_seconds);
    v_row.locked_until := v_lockout_end;

    update app.auth_rate_limit
    set window_started_at = v_row.window_started_at,
        attempt_count = v_row.attempt_count,
        locked_until = v_row.locked_until,
        updated_at = v_now
    where key = p_key;

    return query select
      false,
      0,
      greatest(1, ceil(extract(epoch from (v_lockout_end - v_now)))::integer),
      v_lockout_end;
    return;
  end if;

  update app.auth_rate_limit
  set window_started_at = v_row.window_started_at,
      attempt_count = v_row.attempt_count,
      locked_until = null,
      updated_at = v_now
  where key = p_key;

  return query select
    true,
    greatest(0, p_limit - v_row.attempt_count),
    0,
    null::timestamptz;
end;
$$;

-- reset_rate_limit: clear a key after a successful authentication so a
-- legitimate user does not stay close to the lockout edge from earlier
-- wrong-OTP attempts. Idempotent; no-op when the key has no row.
create or replace function app.reset_rate_limit(p_key text)
returns void
language sql
as $$
  delete from app.auth_rate_limit where key = p_key;
$$;

revoke all on function app.enforce_rate_limit(text, integer, integer, integer) from public;
grant execute on function app.enforce_rate_limit(text, integer, integer, integer) to service_role;

revoke all on function app.reset_rate_limit(text) from public;
grant execute on function app.reset_rate_limit(text) to service_role;
