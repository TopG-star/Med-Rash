-- P0.2 + P0.10 — server-side idempotency for admin writes + identity-claim audit trail.
--
-- ============================================================================
-- 1. app.idempotency_keys
-- ============================================================================
--
-- Caches the response of admin write endpoints (session-create,
-- quiz-bank-write, etc.) keyed by an "Idempotency-Key" request header so a
-- network retry or accidental double-click does not create a duplicate row.
--
-- Lifecycle:
--   * Caller picks (scope, key, request_hash). Helper at
--     admin/netlify/functions/_shared/idempotency.ts wraps the handler.
--   * First call: row is inserted with the eventual response_status +
--     response_body once exec succeeds.
--   * Subsequent calls with the SAME (scope, key) AND SAME request_hash
--     replay the cached 2xx response without re-running the handler.
--   * Subsequent calls with the SAME key but a DIFFERENT request_hash get
--     422 IDEMPOTENCY_KEY_REUSED so we never silently apply two divergent
--     writes under one key.
--
-- Retention: 24h default — long enough to absorb retries from genuinely
-- flaky networks, short enough that the table stays small. The same
-- nightly purge that handles auth_events / admin_audit drains expired
-- rows here too (see admin/netlify/functions/audit-retention-purge.ts).
--
-- RLS: service-role only. Application code never reads this table — the
-- helper module is the sole gateway.

create table if not exists app.idempotency_keys (
  scope            text        not null,
  key              text        not null,
  actor_user_id    uuid                    references auth.users(id) on delete set null,
  request_hash     text        not null,
  response_status  integer     not null,
  response_body    jsonb       not null    default '{}'::jsonb,
  created_at       timestamptz not null    default now(),
  expire_at        timestamptz not null    default (now() + interval '24 hours'),
  primary key (scope, key)
);

create index if not exists idempotency_keys_expire_at_idx
  on app.idempotency_keys (expire_at);

alter table app.idempotency_keys enable row level security;

drop policy if exists idempotency_keys_service_role_all on app.idempotency_keys;
create policy idempotency_keys_service_role_all on app.idempotency_keys
  for all
  to service_role
  using (true)
  with check (true);

-- ============================================================================
-- 2. Identity-claim audit trigger on app.users
-- ============================================================================
--
-- claimed_auth_user_id binds an anonymous participant row to an authenticated
-- Supabase auth.users row (OTP recovery / identity rebind flow, slice 6b).
-- That column is a high-value target for both honest support disputes and
-- malicious takeover attempts, so every write must leave a tamper-evident
-- trail in app.admin_audit even when the change is initiated by a
-- participant flow rather than an admin.
--
-- Behaviour:
--   * Fires on INSERT and UPDATE of app.users when claimed_auth_user_id
--     transitions between null and a uuid, OR between two different uuids.
--   * Writes one row to app.admin_audit with action 'identity_claim' and
--     a metadata payload describing old + new values so a future read-only
--     "recent activity" panel can render it without joining back to users.
--   * actor_user_id falls back to the new claimed_auth_user_id when no
--     application-level actor is known (participant self-rebind via OTP);
--     if neither is available the row is skipped — admin_audit has a NOT
--     NULL constraint on actor_user_id and would otherwise reject the
--     trigger.

create or replace function app.log_identity_claim()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
declare
  v_old_claim uuid;
  v_new_claim uuid;
  v_actor uuid;
begin
  v_old_claim := case when tg_op = 'INSERT' then null else old.claimed_auth_user_id end;
  v_new_claim := new.claimed_auth_user_id;

  if v_old_claim is not distinct from v_new_claim then
    return new;
  end if;

  -- Best-effort actor: the new claim itself when no app-level actor is
  -- propagated (anonymous participant rebinding their own row).
  v_actor := coalesce(v_new_claim, v_old_claim);
  if v_actor is null then
    return new;
  end if;

  insert into app.admin_audit (
    actor_user_id,
    actor_role,
    action,
    target_type,
    target_id,
    payload_hash,
    metadata
  ) values (
    v_actor,
    'participant',
    'identity_claim',
    'app.users',
    new.id::text,
    encode(digest(coalesce(v_old_claim::text, '') || '->' || coalesce(v_new_claim::text, ''), 'sha256'), 'hex'),
    jsonb_build_object(
      'old_claim', v_old_claim,
      'new_claim', v_new_claim,
      'trigger_op', tg_op
    )
  );

  return new;
end;
$$;

drop trigger if exists users_identity_claim_audit on app.users;
create trigger users_identity_claim_audit
  after insert or update of claimed_auth_user_id
  on app.users
  for each row
  execute function app.log_identity_claim();
