-- Slice B1 P2 — TOTP MFA recovery codes for owner-role admins.
--
-- Stores SHA-256 hex hashes of 8 single-use recovery codes per admin.
-- Plaintext codes are shown to the user exactly once at enrollment time
-- and never persisted. Each successful recovery removes the matching
-- hash from the array; when the array is empty the admin must contact
-- another owner for a forced reset.
--
-- Phase 2 of the plan; the column was deliberately deferred from the
-- 006_admin_auth schema because Phase 1 only declared the audit event
-- types, not the enrollment storage.

alter table app.admin_users
  add column if not exists mfa_recovery_codes_hashed text[] not null default '{}',
  add column if not exists mfa_enrolled_at timestamptz;

comment on column app.admin_users.mfa_recovery_codes_hashed is
  'Slice B1 P2: SHA-256 hex hashes of unconsumed MFA recovery codes. Plaintext is shown to the user exactly once at enrollment and never stored. Each successful recovery removes the matching hash.';

comment on column app.admin_users.mfa_enrolled_at is
  'Slice B1 P2: timestamp of the first verified TOTP factor enrollment. Null = no factor ever enrolled. Used by the AAL2 guard in requireAdminSession to decide whether to route owners to /onboarding/mfa (enroll) or to challenge (verify).';
