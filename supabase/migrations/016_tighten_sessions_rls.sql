-- Slice A3 (Pillar 2) — tighten RLS on app.sessions.
--
-- Before this migration, app.sessions had a single policy
-- `sessions_public_select` with `using (true)`, meaning anon-key holders
-- could `select *` from the entire sessions table (host names, join
-- codes, schedules, metadata for every session ever created).
--
-- Audit findings (Slice A3 prep, 2026-05-28):
--   - Every TS caller of `app.sessions` uses the service-role client
--     (session-resolve.ts, session-queries.ts, session-create.ts,
--     reports-queries.ts, overview-queries.ts), which bypasses RLS
--     regardless of policies.
--   - No Dart caller queries `app.sessions` directly; the Flutter app
--     reaches sessions only via the `session-resolve` Netlify function.
--
-- Therefore the surgical correct move is to drop the permissive policy
-- and leave deny-by-default in place for anon/authenticated roles. The
-- service-role policy below is explicit (belt-and-suspenders) and
-- documents intent.
--
-- Deviation from docs/security-hardening-plan.md Slice A3 spec:
--   The plan called for a narrow `sessions_anon_join_lookup` policy
--   gated on `status in ('open','live')`. The `app.sessions` table has
--   no `status` column (lifecycle is expressed through
--   `starts_at`/`ends_at` only). Since no anon caller actually reads
--   the table today, we ship deny-by-default for anon rather than
--   speculatively adding a permissive `[starts_at, ends_at)` window
--   policy that no client needs. If a direct anon read is required in
--   the future, add the narrow policy then with a real consumer in
--   mind.

drop policy if exists sessions_public_select on app.sessions;

drop policy if exists sessions_service_role_all on app.sessions;
create policy sessions_service_role_all on app.sessions
  for all
  to service_role
  using (true)
  with check (true);
