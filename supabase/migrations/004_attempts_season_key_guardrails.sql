-- Enforce season_key at the database layer using Africa/Accra timezone.
-- This guarantees stable monthly partitioning even if clients send bad payloads.

alter table app.attempts
  alter column season_key set default app.current_season_key_ghana(now());

alter table app.attempts
  drop constraint if exists attempts_season_key_format_chk;

alter table app.attempts
  add constraint attempts_season_key_format_chk
  check (season_key ~ '^[0-9]{4}-(0[1-9]|1[0-2])$');

create or replace function app.set_attempt_season_key()
returns trigger
language plpgsql
as $$
begin
  new.season_key := app.current_season_key_ghana(coalesce(new.completed_at, new.started_at, now()));
  return new;
end;
$$;

drop trigger if exists attempts_set_season_key on app.attempts;

create trigger attempts_set_season_key
before insert or update of started_at, completed_at, season_key
on app.attempts
for each row
execute function app.set_attempt_season_key();
