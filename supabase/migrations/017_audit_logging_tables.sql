-- Slice A5 phase 1 (Pillar 6) — audit logging tables.
--
-- Two tables:
--   - app.auth_events: every authentication-related event (OTP request /
--     verify success+fail, allowlist denial, recovery flow, signout, rate
--     limit rejections). Lets us trace who tried to sign in and what
--     happened.
--   - app.admin_audit:  every admin-initiated WRITE on a privileged
--     resource (quiz, question, session, admin_user, onboarding profile).
--     Lets us trace who changed what.
--
-- Privacy discipline (matches Slice A1 rate-limit hashing pattern):
--   * email, ip, user_agent are stored as SHA-256 hex hashes only —
--     enough to correlate same-actor events for investigation, but the
--     original PII cannot be recovered from the table.
--   * For admin_audit, the request payload is stored as a SHA-256 hash
--     too (payload_hash) — proves an action happened and provides a
--     tamper-detection anchor without persisting the full body.
--
-- Retention:
--   * Both tables have expire_at default = now() + 730 days (2 years).
--     A scheduled cleanup job (Slice A5 phase 3) will purge rows past
--     expire_at. 2 years matches typical SOC 2 + GDPR minimisation
--     guidance for security event logs.
--
-- RLS:
--   * Both tables are service-role-only — no anon, no authenticated.
--     Audit data is never directly read by application code; future
--     read paths (admin dashboard "recent activity" tile) will go
--     through dedicated server actions that ALSO use service-role.

-- ============================================================================
-- app.auth_events
-- ============================================================================

create table if not exists app.auth_events (
  id              uuid        primary key default gen_random_uuid(),
  occurred_at     timestamptz not null    default now(),
  expire_at       timestamptz not null    default (now() + interval '730 days'),
  event_type      text        not null,
  user_id         uuid                    references auth.users(id) on delete set null,
  email_hash      text,
  ip_hash         text,
  user_agent_hash text,
  result          text,
  metadata        jsonb       not null    default '{}'::jsonb,
  constraint auth_events_event_type_check check (event_type in (
    'otp_request',
    'otp_verify_success',
    'otp_verify_fail',
    'otp_rate_limited',
    'allowlist_deny',
    'recover_request',
    'recover_verify_success',
    'recover_verify_fail',
    'recover_rate_limited',
    'signout'
  ))
);

create index if not exists auth_events_occurred_at_desc_idx
  on app.auth_events (occurred_at desc);
create index if not exists auth_events_event_type_occurred_at_idx
  on app.auth_events (event_type, occurred_at desc);
create index if not exists auth_events_user_id_occurred_at_idx
  on app.auth_events (user_id, occurred_at desc)
  where user_id is not null;
create index if not exists auth_events_expire_at_idx
  on app.auth_events (expire_at);

alter table app.auth_events enable row level security;

drop policy if exists auth_events_service_role_all on app.auth_events;
create policy auth_events_service_role_all on app.auth_events
  for all
  to service_role
  using (true)
  with check (true);

-- ============================================================================
-- app.admin_audit
-- ============================================================================

create table if not exists app.admin_audit (
  id             uuid        primary key default gen_random_uuid(),
  occurred_at    timestamptz not null    default now(),
  expire_at      timestamptz not null    default (now() + interval '730 days'),
  actor_user_id  uuid        not null    references auth.users(id) on delete restrict,
  actor_role     text        not null,
  action         text        not null,
  target_type    text        not null,
  target_id      text,
  payload_hash   text,
  metadata       jsonb       not null    default '{}'::jsonb
);

create index if not exists admin_audit_occurred_at_desc_idx
  on app.admin_audit (occurred_at desc);
create index if not exists admin_audit_actor_user_id_occurred_at_idx
  on app.admin_audit (actor_user_id, occurred_at desc);
create index if not exists admin_audit_action_occurred_at_idx
  on app.admin_audit (action, occurred_at desc);
create index if not exists admin_audit_target_type_id_occurred_at_idx
  on app.admin_audit (target_type, target_id, occurred_at desc);
create index if not exists admin_audit_expire_at_idx
  on app.admin_audit (expire_at);

alter table app.admin_audit enable row level security;

drop policy if exists admin_audit_service_role_all on app.admin_audit;
create policy admin_audit_service_role_all on app.admin_audit
  for all
  to service_role
  using (true)
  with check (true);
