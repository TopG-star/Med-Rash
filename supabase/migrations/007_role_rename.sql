-- 007_role_rename.sql
-- Renames admin_users role values from admin/superadmin to host/owner.
-- This matches the user-facing language ("Host" runs sessions, "Owner" runs
-- the platform) and removes the ambiguous "Super Admin" wording.
--
-- - admin       → host  (default for new rows)
-- - superadmin  → owner

begin;

alter table app.admin_users
  drop constraint if exists admin_users_role_check;

update app.admin_users set role = 'host'  where role = 'admin';
update app.admin_users set role = 'owner' where role = 'superadmin';

alter table app.admin_users
  add constraint admin_users_role_check
  check (role in ('host', 'owner'));

alter table app.admin_users
  alter column role set default 'host';

commit;

notify pgrst, 'reload schema';
