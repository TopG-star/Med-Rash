create extension if not exists pgcrypto;

create schema if not exists app;

create type app.attempt_mode as enum ('learning', 'ranked');
create type app.attempt_origin as enum ('qr_session', 'open_access');

create or replace function app.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists app.users (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  nickname text not null,
  facility text not null,
  specialty text not null,
  profession text,
  claimed_auth_user_id uuid unique,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create unique index if not exists users_nickname_lower_idx
  on app.users (lower(nickname));

create table if not exists app.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  device_install_id text not null unique,
  is_primary boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists app.quizzes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  category text not null,
  summary text not null,
  question_count_default integer not null check (question_count_default between 1 and 50),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists app.questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references app.quizzes(id) on delete cascade,
  prompt text not null,
  options jsonb not null,
  correct_index integer not null check (correct_index >= 0),
  explanation text not null,
  clinical_area text,
  tags text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint questions_options_array_chk check (jsonb_typeof(options) = 'array'),
  constraint questions_options_count_chk check (jsonb_array_length(options) between 2 and 6)
);

create table if not exists app.sessions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references app.quizzes(id) on delete cascade,
  name text not null,
  join_code text not null unique,
  host_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sessions_date_order_chk check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create table if not exists app.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  quiz_id uuid not null references app.quizzes(id) on delete cascade,
  session_id uuid references app.sessions(id) on delete set null,
  mode app.attempt_mode not null,
  origin app.attempt_origin not null default 'open_access',
  score integer not null default 0,
  total_questions integer not null check (total_questions between 1 and 50),
  time_taken_ms integer not null default 0 check (time_taken_ms >= 0),
  season_key text not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint attempts_score_range_chk check (score between 0 and total_questions)
);

create unique index if not exists attempts_ranked_once_per_quiz_idx
  on app.attempts (user_id, quiz_id)
  where mode = 'ranked';

create index if not exists attempts_session_idx
  on app.attempts (session_id);

create index if not exists attempts_quiz_mode_completed_idx
  on app.attempts (quiz_id, mode, completed_at desc);

create index if not exists attempts_origin_idx
  on app.attempts (origin, completed_at desc);

create index if not exists attempts_season_mode_idx
  on app.attempts (season_key, mode);

create table if not exists app.answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references app.attempts(id) on delete cascade,
  question_id uuid not null references app.questions(id) on delete cascade,
  selected_index integer not null check (selected_index >= 0),
  selected_option_text text not null,
  is_correct boolean not null,
  response_time_ms integer not null default 0 check (response_time_ms >= 0),
  notes jsonb not null default '{}'::jsonb,
  answered_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);

create index if not exists answers_question_correct_idx
  on app.answers (question_id, is_correct);

create index if not exists answers_attempt_idx
  on app.answers (attempt_id);

drop trigger if exists users_set_updated_at on app.users;
create trigger users_set_updated_at
before update on app.users
for each row
execute function app.set_updated_at();

drop trigger if exists quizzes_set_updated_at on app.quizzes;
create trigger quizzes_set_updated_at
before update on app.quizzes
for each row
execute function app.set_updated_at();

drop trigger if exists sessions_set_updated_at on app.sessions;
create trigger sessions_set_updated_at
before update on app.sessions
for each row
execute function app.set_updated_at();

alter table app.users enable row level security;
alter table app.user_devices enable row level security;
alter table app.quizzes enable row level security;
alter table app.questions enable row level security;
alter table app.sessions enable row level security;
alter table app.attempts enable row level security;
alter table app.answers enable row level security;

drop policy if exists users_service_role_all on app.users;
create policy users_service_role_all on app.users
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists user_devices_service_role_all on app.user_devices;
create policy user_devices_service_role_all on app.user_devices
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists quizzes_public_select on app.quizzes;
create policy quizzes_public_select on app.quizzes
for select
using (is_active = true or auth.role() = 'service_role');

drop policy if exists questions_public_select on app.questions;
create policy questions_public_select on app.questions
for select
using (
  is_active = true
  or auth.role() = 'service_role'
);

drop policy if exists sessions_public_select on app.sessions;
create policy sessions_public_select on app.sessions
for select
using (true);

drop policy if exists attempts_service_role_all on app.attempts;
create policy attempts_service_role_all on app.attempts
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists answers_service_role_all on app.answers;
create policy answers_service_role_all on app.answers
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists users_claimed_self_select on app.users;
create policy users_claimed_self_select on app.users
for select
using (claimed_auth_user_id = auth.uid());

drop policy if exists users_claimed_self_update on app.users;
create policy users_claimed_self_update on app.users
for update
using (claimed_auth_user_id = auth.uid())
with check (claimed_auth_user_id = auth.uid());

drop policy if exists attempts_claimed_self_select on app.attempts;
create policy attempts_claimed_self_select on app.attempts
for select
using (
  exists (
    select 1
    from app.users u
    where u.id = attempts.user_id
      and u.claimed_auth_user_id = auth.uid()
  )
);

drop policy if exists answers_claimed_self_select on app.answers;
create policy answers_claimed_self_select on app.answers
for select
using (
  exists (
    select 1
    from app.attempts a
    join app.users u on u.id = a.user_id
    where a.id = answers.attempt_id
      and u.claimed_auth_user_id = auth.uid()
  )
);