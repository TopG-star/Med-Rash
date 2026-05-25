-- Slice 6b: OTP-confirmed identity rebind on a new device.
--
-- When a returning user verifies an OTP for an email captured in 6a, the
-- freshly-minted guest user_id on the new install must be merged into the
-- original (recovered) user_id so the user keeps their attempts, ranked
-- best scores, and device binding.
--
-- claimed_auth_user_id is already UNIQUE on app.users (migration 001) so
-- no extra index is needed; the same column now plays its intended role
-- as the link between Supabase Auth and our domain user.

create or replace function app.merge_user_into(
  source_user_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = app, pg_catalog
as $$
declare
  conflict record;
begin
  if source_user_id is null or target_user_id is null then
    raise exception 'merge_user_into requires both ids' using errcode = '22023';
  end if;

  if source_user_id = target_user_id then
    return;
  end if;

  if not exists (select 1 from app.users where id = source_user_id) then
    raise exception 'source user % not found', source_user_id using errcode = 'P0002';
  end if;

  if not exists (select 1 from app.users where id = target_user_id) then
    raise exception 'target user % not found', target_user_id using errcode = 'P0002';
  end if;

  -- Ranked attempts have a unique (user_id, quiz_id) where mode='ranked'.
  -- For every quiz where BOTH source and target hold a ranked attempt,
  -- delete the loser (lower score; tie-break: keep the earlier completion
  -- on the target side so historical ranking stays stable).
  for conflict in
    select s.id as source_attempt_id, t.id as target_attempt_id
    from app.attempts s
    join app.attempts t
      on t.user_id = target_user_id
     and t.quiz_id = s.quiz_id
     and t.mode = 'ranked'
    where s.user_id = source_user_id
      and s.mode = 'ranked'
  loop
    delete from app.attempts a
    using app.attempts s, app.attempts t
    where s.id = conflict.source_attempt_id
      and t.id = conflict.target_attempt_id
      and a.id = case
        when s.score > t.score then t.id
        when s.score < t.score then s.id
        when s.completed_at is not null
         and (t.completed_at is null or s.completed_at < t.completed_at)
          then t.id
        else s.id
      end;
  end loop;

  -- Re-point remaining attempts (ranked winners + all learning attempts).
  -- answers cascade-deletes from attempts, so nothing else to touch there.
  update app.attempts
    set user_id = target_user_id
  where user_id = source_user_id;

  -- Devices: user_devices has UNIQUE(device_install_id) but no unique on
  -- user_id, so a straight re-point is safe. The recovered profile now
  -- owns this device install.
  update app.user_devices
    set user_id = target_user_id
  where user_id = source_user_id;

  -- Session join events key on text participant_id with UNIQUE(session_id,
  -- participant_id). Drop source rows that would collide; re-point the rest.
  delete from app.session_join_events sje
  where sje.participant_id = source_user_id::text
    and exists (
      select 1 from app.session_join_events other
      where other.session_id = sje.session_id
        and other.participant_id = target_user_id::text
    );

  update app.session_join_events
    set participant_id = target_user_id::text
  where participant_id = source_user_id::text;

  -- Finally, retire the orphaned guest row. No FKs reference it any more.
  delete from app.users where id = source_user_id;
end;
$$;

revoke all on function app.merge_user_into(uuid, uuid) from public;
grant execute on function app.merge_user_into(uuid, uuid) to service_role;
