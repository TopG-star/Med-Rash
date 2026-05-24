-- 008_host_profile_and_status.sql
-- Adds host profile fields (full_name, company, job_role) and an explicit
-- lifecycle column (status) to app.admin_users. Backfills existing rows so
-- they preserve current behavior (active vs deactivated).
--
-- Lifecycle states:
--   invited     - row created via inviteAdminAction, no first sign-in yet
--   verified    - first OTP/link verified, profile incomplete -> /onboarding
--   active      - profile submitted, can use portal
--   deactivated - soft removed (also is_active=false)
--
-- This migration NEVER writes to auth.users.

begin;

-- 1. Profile fields (nullable; populated by /onboarding).
alter table app.admin_users
  add column if not exists full_name text,
  add column if not exists company   text,
  add column if not exists job_role  text
    check (job_role is null or job_role in ('MSR', 'Manager'));

-- 2. Lifecycle column. Default 'invited' is correct for new invites;
--    existing rows are backfilled below.
alter table app.admin_users
  add column if not exists status text not null default 'invited'
    check (status in ('invited', 'verified', 'active', 'deactivated'));

-- 3. Backfill existing rows: preserve current behavior.
--    Active rows (is_active=true) -> 'active'. Inactive -> 'deactivated'.
update app.admin_users
   set status = case when is_active then 'active' else 'deactivated' end
 where status = 'invited';

create index if not exists admin_users_status_idx
  on app.admin_users(status);

commit;

notify pgrst, 'reload schema';
