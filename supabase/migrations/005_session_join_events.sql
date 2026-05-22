-- Lightweight join-event log so the admin Live view can distinguish
-- "nobody scanned the code" from "people scanned but no attempts submitted"
-- (e.g. blocked by ranked-eligibility, network failure, or abandoned).
--
-- Dedupe is per (session_id, participant_id) so the count reflects unique
-- participants, not raw scans. session-resolve.ts upserts idempotently.

create table if not exists app.session_join_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references app.sessions(id) on delete cascade,
  participant_id text not null,
  device_install_id text,
  resolved_at timestamptz not null default now(),
  constraint session_join_events_session_participant_unique
    unique (session_id, participant_id)
);

create index if not exists session_join_events_session_idx
  on app.session_join_events (session_id);

-- Service role only — clients never touch this directly.
alter table app.session_join_events enable row level security;
