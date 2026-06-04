-- ============================================================================
-- MedRash pilot reset — wipe all non-operator data for a fresh first-run.
-- ============================================================================
--
-- WHAT THIS DOES
--   Empties every table that holds participant, quiz, session, attempt,
--   answer, and device data so the production database looks like a
--   freshly-deployed app. The operator surface (admin_users + the matching
--   auth.users rows) is preserved.
--
-- WHAT SURVIVES
--   app.admin_users WHERE role = 'owner'
--     OR (role = 'host' AND is_active = true)
--   …plus the matching auth.users rows for those admins.
--
--   app.auth_events       — forensic auth log (kept intact)
--   app.admin_audit       — except identity_claim rows tied to wiped users
--                            (see "FORCED TRADE-OFF" below)
--   app.idempotency_keys  — kept intact (will auto-expire)
--   app.auth_rate_limit   — kept intact (transient anyway)
--   Database schema / migrations / RPCs / views / triggers — untouched
--   Storage buckets / Edge Function code — untouched
--
-- WHAT GETS DESTROYED
--   app.answers, app.attempts, app.session_join_events, app.sessions,
--   app.questions, app.quizzes, app.user_devices, app.users
--   …and every auth.users row NOT in the keep set.
--   …and every app.admin_users row NOT in the keep set (deactivated /
--      invited-only operators).
--
-- FORCED TRADE-OFF
--   The trigger users_identity_claim_audit writes an app.admin_audit row
--   every time a participant claims an auth.users id (action='identity_claim',
--   actor_user_id = the participant's auth.users.id). admin_audit.actor_user_id
--   is NOT NULL with ON DELETE RESTRICT, so the wipe cannot delete the matching
--   auth.users row until the identity_claim audit row is gone. This script
--   deletes ONLY identity_claim rows whose actor is being removed. All other
--   audit actions (admin logins, user_erased, MFA changes, etc.) are preserved.
--
-- IRREVERSIBLE
--   The whole script runs in one transaction. Nothing commits until the
--   final COMMIT. To dry-run, change the final COMMIT to ROLLBACK and read
--   the NOTICE output to see the row counts that would be affected.
--
-- WHERE TO RUN
--   Supabase Dashboard → SQL Editor → paste this whole file → Run.
--   Or psql with the project's pooled connection string.
--   Requires service_role / postgres-level privileges (it touches auth.users).
--
-- ============================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- 1. Snapshot the keep set.
create temporary table _medrash_keep_users on commit drop as
select user_id
from app.admin_users
where role = 'owner'
   or (role = 'host' and is_active = true);

-- 2. Refuse to run if there is nobody to keep — wiping every operator would
--    lock you out of the admin app.
do $$
declare
  v_keep int;
begin
  select count(*) into v_keep from _medrash_keep_users;
  if v_keep = 0 then
    raise exception
      'Pilot reset aborted: keep set is empty (no role=owner and no active hosts in app.admin_users).';
  end if;
  raise notice 'KEEP SET: % admin_users rows will be preserved.', v_keep;
end $$;

-- 3. Pre-wipe snapshot for the operator log.
do $$
declare
  c_answers int; c_attempts int; c_joins int; c_sessions int;
  c_questions int; c_quizzes int; c_devices int; c_users int;
  c_admin int; c_auth int;
begin
  select count(*) into c_answers   from app.answers;
  select count(*) into c_attempts  from app.attempts;
  select count(*) into c_joins     from app.session_join_events;
  select count(*) into c_sessions  from app.sessions;
  select count(*) into c_questions from app.questions;
  select count(*) into c_quizzes   from app.quizzes;
  select count(*) into c_devices   from app.user_devices;
  select count(*) into c_users     from app.users;
  select count(*) into c_admin     from app.admin_users;
  select count(*) into c_auth      from auth.users;

  raise notice 'PRE-WIPE: answers=% attempts=% join_events=% sessions=% questions=% quizzes=% devices=% users=% admin_users=% auth.users=%',
    c_answers, c_attempts, c_joins, c_sessions, c_questions, c_quizzes,
    c_devices, c_users, c_admin, c_auth;
end $$;

-- 4. Wipe content/session/attempt data.
--    FK cascades would handle most of this automatically, but explicit deletes
--    in dependency order make the row-count notices accurate and the intent
--    obvious during code review.
delete from app.answers;
delete from app.attempts;
delete from app.session_join_events;
delete from app.sessions;
delete from app.questions;
delete from app.quizzes;
delete from app.user_devices;

-- 5. Drop identity_claim audit rows whose actor is about to be removed
--    (see FORCED TRADE-OFF in the header). This is the minimum scrub required
--    to let the auth.users delete in step 8 succeed without violating the
--    admin_audit RESTRICT FK.
delete from app.admin_audit
where action = 'identity_claim'
  and actor_user_id is not null
  and actor_user_id not in (select user_id from _medrash_keep_users);

-- 6. Wipe participant rows in app.users (no FK out to auth.users, safe in any order).
delete from app.users;

-- 7. Wipe non-keep admin_users rows (deactivated hosts, invited-only operators).
delete from app.admin_users
where user_id not in (select user_id from _medrash_keep_users);

-- 8. Final guard: refuse to delete auth.users if any non-identity_claim audit
--    row still references a soon-to-be-deleted auth.users id. This catches any
--    unexpected audit row written by future code that we did not anticipate
--    here, instead of failing mid-delete with an opaque FK error.
do $$
declare
  v_blocking int;
begin
  select count(*) into v_blocking
  from app.admin_audit a
  where a.actor_user_id is not null
    and a.actor_user_id not in (select user_id from _medrash_keep_users);

  if v_blocking > 0 then
    raise exception
      'Pilot reset aborted: % admin_audit row(s) still reference auth.users id(s) outside the keep set. Inspect: select id, action, target_type, actor_user_id from app.admin_audit where actor_user_id not in (select user_id from app.admin_users where role = ''owner'' or (role = ''host'' and is_active = true)); — then decide whether to keep those audit rows (by keeping the corresponding auth.users) or delete them.',
      v_blocking;
  end if;
end $$;

-- 9. Wipe auth.users outside the keep set (cascades into auth.identities,
--    auth.sessions, auth.refresh_tokens, etc. via Supabase auth schema FKs).
delete from auth.users
where id not in (select user_id from _medrash_keep_users);

-- 10. Post-wipe verification.
do $$
declare
  c_answers int; c_attempts int; c_joins int; c_sessions int;
  c_questions int; c_quizzes int; c_devices int; c_users int;
  c_admin int; c_auth int;
begin
  select count(*) into c_answers   from app.answers;
  select count(*) into c_attempts  from app.attempts;
  select count(*) into c_joins     from app.session_join_events;
  select count(*) into c_sessions  from app.sessions;
  select count(*) into c_questions from app.questions;
  select count(*) into c_quizzes   from app.quizzes;
  select count(*) into c_devices   from app.user_devices;
  select count(*) into c_users     from app.users;
  select count(*) into c_admin     from app.admin_users;
  select count(*) into c_auth      from auth.users;

  raise notice 'POST-WIPE: answers=% attempts=% join_events=% sessions=% questions=% quizzes=% devices=% users=% admin_users=% auth.users=%',
    c_answers, c_attempts, c_joins, c_sessions, c_questions, c_quizzes,
    c_devices, c_users, c_admin, c_auth;

  if c_users <> 0 or c_quizzes <> 0 or c_sessions <> 0 or c_attempts <> 0 then
    raise exception 'Pilot reset verification failed: residual rows in participant/quiz/session/attempt tables.';
  end if;
end $$;

-- Change the line below to ROLLBACK to dry-run.
commit;
