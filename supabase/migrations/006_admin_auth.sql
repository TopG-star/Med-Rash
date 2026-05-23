-- 006_admin_auth.sql
-- Adds the admin_users allowlist (role + soft-deactivate + invite trail) and
-- attaches created_by attribution to quizzes, sessions, and questions.
-- Pre-auth rows keep created_by = NULL (rendered as "Pre-auth seed" in UI).
-- This migration NEVER writes to auth.users.

begin;

create extension if not exists citext;

-- 1. Allowlist of admins (subset of auth.users)
create table if not exists app.admin_users (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       citext not null unique,
  role        text not null default 'admin'
                check (role in ('admin', 'superadmin')),
  is_active   boolean not null default true,
  invited_by  uuid references app.admin_users(user_id) on delete set null,
  invited_at  timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists admin_users_active_idx
  on app.admin_users(is_active)
  where is_active;

-- 2. created_by attribution. Nullable: NULL = pre-auth seed.
alter table app.quizzes
  add column if not exists created_by uuid references auth.users(id) on delete set null;

alter table app.sessions
  add column if not exists created_by uuid references auth.users(id) on delete set null;

alter table app.questions
  add column if not exists created_by uuid references auth.users(id) on delete set null;

create index if not exists quizzes_created_by_idx   on app.quizzes(created_by);
create index if not exists sessions_created_by_idx  on app.sessions(created_by);
create index if not exists questions_created_by_idx on app.questions(created_by);

commit;
