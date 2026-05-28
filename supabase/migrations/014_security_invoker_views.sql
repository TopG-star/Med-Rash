-- Slice A3 (Pillar 2) — convert leaderboard views to security_invoker.
--
-- Without this, the views run with the owner's privileges (effectively
-- security_definer), which Supabase's database linter flags and which
-- silently bypasses RLS on the underlying tables. With security_invoker,
-- the underlying SELECTs run as the calling role, so RLS on `app.attempts`
-- and `app.users` is honored end-to-end.
--
-- Safe because:
--   - Both views are consumed only through SQL functions
--     `app.leaderboard_all_time` / `app.leaderboard_monthly`, which are
--     invoked by Netlify functions using the service-role client (bypasses
--     RLS regardless).
--   - No anon/authenticated caller queries these views directly.

alter view app.ranked_attempt_totals_all_time
  set (security_invoker = true);

alter view app.ranked_attempt_totals_monthly
  set (security_invoker = true);
