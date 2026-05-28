-- Slice A3 (Pillar 2) — enable RLS on app.admin_users.
--
-- Before this migration, app.admin_users had no RLS at all (the only
-- table in the `app` schema in that state). Every read/write today goes
-- through the service-role client (`getSupabaseAdminClient` /
-- `getAdminSupabaseClient`), so enabling RLS is a no-op for current
-- code paths but eliminates the risk that a leaked anon key or a future
-- authenticated-session caller could enumerate or modify admin records.
--
-- Policies:
--   - admin_users_service_role_all: explicit allow for service_role
--     (redundant — service_role bypasses RLS — but documents intent and
--     survives any future Supabase change to that bypass behavior).
--   - admin_users_self_select: an authenticated user may read only their
--     own admin record (used as defence-in-depth if an admin SSR caller
--     ever switches from service-role to user-session reads to check
--     their own status/role).
--   - Everything else (insert/update/delete from non-service-role,
--     select for other users' rows) is denied by default.

alter table app.admin_users enable row level security;

drop policy if exists admin_users_service_role_all on app.admin_users;
create policy admin_users_service_role_all on app.admin_users
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists admin_users_self_select on app.admin_users;
create policy admin_users_self_select on app.admin_users
  for select
  to authenticated
  using (auth.uid() = user_id);
