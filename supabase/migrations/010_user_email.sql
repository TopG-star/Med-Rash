-- Slice 6a: optional recovery email on app.users.
--
-- Nullable so existing profiles and skip-the-field users stay valid. The
-- partial UNIQUE index on lower(email) mirrors users_nickname_lower_idx
-- (same convention, no extension dependency) and produces a 23505 the
-- backend translates into HTTP 409 EMAIL_TAKEN. Slice 6b will use this
-- column plus claimed_auth_user_id to drive OTP-confirmed device rebind.

alter table app.users
  add column if not exists email text;

create unique index if not exists users_email_lower_idx
  on app.users (lower(email))
  where email is not null;
