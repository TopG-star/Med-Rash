# MedRash Disaster Recovery Runbook

> Slice B6 of [`security-hardening-plan.md`](../security-hardening-plan.md). Procedures for restoring service after data loss, account/org compromise, or vendor-side disruption.

**Last reviewed**: 2026-05 (initial draft).
**Owner**: Product.
**Review cadence**: quarterly + after every drill + after every SEV1 incident.

> **Relationship to [incident-response.md](incident-response.md)**: the incident runbook handles **detection → containment → comms**. This DR runbook handles **restoration of service and data** once containment is in place. Both are invoked together for SEV1 events.

---

## 1. RTO / RPO targets (pilot)

| Surface | RTO (max time to restore) | RPO (max acceptable data loss) | Backup mechanism |
|---|---|---|---|
| Admin portal (Next.js on Netlify) | 1 h | 0 — code is in git, redeploy from `main` | Source on GitHub + Netlify redeploy |
| Participant app (Flutter on Netlify) | 1 h | 0 — same as admin | Source on GitHub + Netlify redeploy |
| Postgres (Supabase) | 4 h | **5 min** if on Pro+ (PITR); **24 h** if on Free (daily snapshot) | Supabase PITR or daily backup |
| Audit log (rows in Postgres) | 4 h | same as DB | Same as Postgres |
| Secrets (Netlify env vars) | 1 h after rotation kit retrieved | n/a (regenerated, not restored) | Offline rotation kit (see §6) |
| Domain (DNS, registrar) | 24 h | n/a | Registrar account + 2FA + recovery email |

**Pilot acceptance**: a 4-hour RTO and 24-hour RPO is the worst-case baseline. Once the pilot graduates to production, both must tighten — RTO ≤1 h and RPO ≤5 min are the targets for any scenario where hospital-grade reliability is implied.

---

## 2. Current Supabase backup posture (FILL IN before pilot launch)

The applicable procedure differs by Supabase plan. Capture the live answer here and update on every plan change.

- [ ] **Project ref**: `___________________________________`
- [ ] **Plan tier**: `[ ] Free  /  [ ] Pro  /  [ ] Team  /  [ ] Enterprise`
- [ ] **PITR available**: `[ ] Yes (Pro+ — 7-day window default)  /  [ ] No (Free — daily snapshot only, 7-day retention)`
- [ ] **Last verified by going to**: Supabase Dashboard → Project → Database → Backups
- [ ] **Verified on**: `YYYY-MM-DD`

Once this is filled in, the rest of the runbook references the active path. If on Free, **upgrade to Pro before pilot launch is strongly recommended** — Free tier RPO of up to 24 h is incompatible with the audit log integrity claim in [security-hardening-plan.md](../security-hardening-plan.md).

---

## 3. Scenario playbooks

Each scenario lists: trigger → containment cross-link → restore procedure → verification → post-restore actions.

### 3.1 Application code corruption / bad deploy

**Trigger**: latest Netlify deploy is broken or contains a bug requiring rollback.

**Containment**: [incident-response.md §3](incident-response.md#3-detection--triage--response--recovery) for triage.

**Restore**:

1. Netlify Dashboard → Site → Deploys → find last known-good deploy → "Publish deploy".
2. If the bad commit is on `main`, open a `fix/revert-<sha>` branch, `git revert <sha>`, PR + merge.
3. CI ([ci.yml](../../.github/workflows/ci.yml)) must pass on the revert PR — no `--no-verify` shortcuts.

**Verification**: `curl https://medrash-admin.netlify.app/api/health` returns 200; manual smoke on `/login` + `/sessions`.

**Post-restore**: file post-mortem within 7 days; consider adding a regression test for the failure mode.

---

### 3.2 Postgres data loss (accidental delete, bad migration, corruption)

**Trigger**: an `app.*` table is missing rows, or a migration applied incorrect changes, or Supabase reports DB corruption.

**Containment**: switch participant surface to read-only mode ([incident-response.md §5.2](incident-response.md#52-read-only-mode-for-participant-surface)); disable any cron functions that write (`audit-retention-purge`).

**Restore — PATH A: Pro+ with PITR (preferred)**:

1. Supabase Dashboard → Project → Database → Backups → "Point in Time".
2. Choose a recovery timestamp **at least 5 minutes before** the incident detection time.
3. Supabase will spin up a recovery branch — review the data there first, **do not** overwrite production until reviewed.
4. Once verified, promote the recovery branch OR export the affected tables via `pg_dump` from the recovery branch and `pg_restore` selected tables into production.
5. Re-enable participant writes.

**Restore — PATH B: Free with daily snapshot only**:

1. Supabase Dashboard → Project → Database → Backups → "Daily backups".
2. Choose the most recent snapshot taken before the incident.
3. Same review-then-promote flow as PATH A.
4. **Accept the data loss window** between the snapshot timestamp and the incident — communicate this to affected tenants per [incident-response.md §4](incident-response.md#4-external-communications--gdpr).

**Verification**: row counts on key tables (`app.users`, `app.sessions`, `app.attempts`, `app.auth_events`, `app.admin_audit`) match expected; spot-check a known participant flow end-to-end.

**Post-restore**: audit log gap analysis — any audit events lost in the restore window must be reconstructed from Netlify function logs if possible, otherwise documented as a known gap.

---

### 3.3 Supabase project suspended or deleted (vendor side)

**Trigger**: Supabase support disables the project (billing dispute, ToS violation, security action) or the project is accidentally deleted.

**Containment**: full read-only freeze (admin portal returns maintenance page); open vendor support ticket immediately ([vendor-register.md](vendor-register.md) for contact).

**Restore**:

1. **If suspended**: resolve the underlying issue with Supabase support; project is restored without data loss.
2. **If deleted but within Supabase's deletion grace period (typically 7 days for paid plans)**: open emergency support ticket and request restoration.
3. **If deleted beyond grace period**: re-create the project from migrations:
   - `cd supabase && supabase db reset --linked` (after `supabase link --project-ref <new-ref>`)
   - Apply migrations 001–017 (or whatever the head is at time of restore) via `supabase db push`.
   - Restore most recent backup snapshot file if exported offline; if no offline backup exists, **data prior to the deletion is unrecoverable** — accept the data loss and notify per GDPR Art. 33.
4. Rotate every secret tied to the old project ref (see §6).

**Verification**: schema applied (`select * from supabase_migrations.schema_migrations` shows expected hashes); admin portal logs in; participant flow works.

**Post-restore**: document new project ref in [vendor-register.md](vendor-register.md) and `docs/dev-environment.md`; revisit "no offline backup" finding and ship an automated weekly `pg_dump` to offsite storage if it does not exist (currently an open action).

---

### 3.4 Netlify account / org compromise or lockout

**Trigger**: Netlify account credentials compromised, or owner loses access (lost 2FA device, account ban).

**Containment**: contact Netlify support; ALSO contact registrar to ensure DNS is not pointed at attacker-controlled origin (see §3.5).

**Restore**:

1. **Compromise (account access intact)**: rotate Netlify password + revoke all personal access tokens (Settings → Applications) + re-enable 2FA with a fresh device + invalidate all active sessions.
2. **Lockout (no access)**: Netlify support recovery process — requires email account proof + payment method proof. Allow 1–3 business days.
3. **While locked out**: temporarily redirect DNS to a maintenance page hosted on a different provider (e.g., a static GitHub Pages site) so users see a coordinated message rather than a stale or hijacked page.
4. **After recovery**: rotate every Netlify-stored secret (see §6) under the assumption they were exposed during the compromise window.

**Verification**: log into Netlify, check deploy history for unauthorized deploys, check function logs for unauthorized invocations, confirm site is serving expected commit SHA.

**Post-restore**: enable Netlify SAML/SSO when team grows beyond 2; record incident in [vendor-register.md](vendor-register.md) audit notes.

---

### 3.5 Domain hijack (DNS or registrar compromise)

**Trigger**: traffic to `medrash.*` is being served from an unauthorized origin, or registrar reports account access changes you did not make.

**Containment**: this is **SEV1** by default. Treat all sessions issued during the suspected window as compromised. Rotate `MEDRASH_ADMIN_SESSION_SECRET` (see [incident-response.md §5.1](incident-response.md#51-suspected-stolen-admin-session)) and `MEDRASH_DEVICE_TOKEN_SECRET` immediately to invalidate everything in flight.

**Restore**:

1. Contact registrar support immediately — most registrars have a 24/7 abuse line. Provide proof of ownership (original payment method, original signup email with full headers, government ID if asked).
2. Once registrar control is restored: rotate registrar password + enable registry lock (if supported — `clientTransferProhibited` + `clientDeleteProhibited` EPP codes) + enforce 2FA with a hardware key.
3. Audit DNS records — restore any tampered entries from a known-good export. Maintain a committed `docs/security/dns-export-YYYYMMDD.md` snapshot quarterly so there is an authoritative reference.
4. Issue user communication: anyone who interacted with the domain during the hijack window may have seen a phishing page — assume credentials in that window are compromised even though MedRash didn't issue them, and ask users to rotate their email password as a precaution.

**Verification**: `dig +short medrash.<tld>` resolves to expected IP / Netlify CNAME from multiple resolvers; TLS certificate (`openssl s_client -connect medrash.<tld>:443`) matches expected issuer + SANs.

**Post-restore**: file as SEV1 post-mortem; consider moving registrar to a more security-conscious provider if the current one's recovery experience was poor.

---

### 3.6 Secret leak (one or more credentials exposed)

**Trigger**: gitleaks ([security.yml](../../.github/workflows/security.yml)) flags a commit, dependabot reports a leaked token, a developer accidentally pastes a secret in chat/email/screenshot, or `MEDRASH_ADMIN_SESSION_SECRET` rotation log shows unaccounted access.

**Containment**: rotate the affected secret(s) immediately per §6. **Do NOT force-push history to "remove" the leak** — the secret is already in clones, mirrors, and possibly GitHub's cache; rotation is the only correct response.

**Restore**: see §6 rotation procedure.

**Verification**: confirm new secret is in use by checking a fresh deploy log + a smoke test against the affected endpoint; the old secret should fail authentication.

**Post-restore**: add the leak path to gitleaks ignore (`.gitleaksignore`) ONLY if it was a false positive; otherwise leave the historical commit findable so it's not re-leaked. If the leak was via a developer process (chat, screenshot), update the developer onboarding doc.

---

## 4. Quarterly restore drill { #quarterly-drill }

A drill MUST be performed every quarter. Skipping a drill = SEV3 self-reported incident.

### 4.1 Drill procedure (PITR-based)

1. Pick a non-production "staging" Supabase project (create one if none exists — Pro plan supports multiple projects).
2. Note current timestamp `T0`.
3. In production, find a small, well-known row (e.g., a test session created specifically for the drill).
4. Wait 10 minutes (`T0 + 10`).
5. In Supabase Dashboard for staging: trigger a PITR restore from production to `T0` (uses Supabase's project-to-project restore feature; if not available on plan, use `pg_dump` → `pg_restore` via local).
6. Verify the well-known row exists in staging.
7. Verify a row created at `T0 + 5` is **absent** from staging (proves the snapshot is bounded).
8. Time the entire procedure from step 5 to step 7 — this is the drill RTO.
9. Tear down staging restore artifacts.

### 4.2 Drill log

Append one row per drill. Newest on top.

| Drill date | Performed by | Source plan tier | Procedure (PITR / snapshot) | Drill RTO | Outcome | Notes / follow-ups |
|---|---|---|---|---|---|---|
| _YYYY-MM-DD_ | _owner_ | _Free/Pro/Team_ | _PITR / daily snapshot / pg_dump_ | _Nh Nm_ | _PASS / PARTIAL / FAIL_ | _link to incident if FAIL_ |

> **First drill must be performed before pilot launch**, then quarterly thereafter. Add a calendar reminder.

---

## 5. Offsite backup (open action — recommended before pilot launch)

Supabase backups live in Supabase. If Supabase's account is locked or the project is deleted beyond grace period, those backups are inaccessible. Mitigate by:

1. Scheduled weekly `pg_dump` triggered by a Netlify scheduled function OR GitHub Actions workflow.
2. Encrypted upload (age or gpg, key held offline) to a different vendor (e.g., a B2 / S3 / R2 bucket — pick one whose account is NOT linked to the same email / payment method as Supabase / Netlify).
3. Retain 12 monthly snapshots + 4 weekly snapshots.
4. Document the encryption key custody in [vendor-register.md](vendor-register.md) — the key, not the password, is the irreplaceable artifact.

**Status**: not yet implemented. Tracked as a B6 open action in [security-hardening-plan.md](../security-hardening-plan.md).

---

## 6. Secret rotation kit { #secret-rotation-kit }

Every secret has: a name, a generator command, a deployment location (where the new value goes), and a "what breaks if missing" line. Rotation is non-destructive — generate new, deploy new, observe, then revoke old.

| Secret | Generator | Deploy to | Breakage on miss |
|---|---|---|---|
| `MEDRASH_ADMIN_SESSION_SECRET` | `openssl rand -hex 32` (≥32 chars) | Netlify env (admin site) → redeploy | All admin sessions invalidated → users see `/login?reason=session_*` |
| `MEDRASH_DEVICE_TOKEN_SECRET` | `openssl rand -hex 32` | Netlify env (functions site) → redeploy | All participant bearers invalidated → app re-mints automatically via Turnstile |
| `MEDRASH_TURNSTILE_SECRET_KEY` | Cloudflare dashboard → Turnstile → Rotate | Netlify env → redeploy | New tokens fail challenge → bootstrap mint blocked |
| Supabase `service_role` key | Supabase Dashboard → Settings → API → Reset | Netlify env (every function reading it) → redeploy | All Netlify functions return 500 on DB call |
| Supabase `anon` key | Same as above | Netlify env (admin + app build args) → redeploy | Public reads (leaderboard) fail |
| Netlify deploy access token (CLI/CI) | Netlify Dashboard → User Settings → Applications → New token | Local + CI secret store | CI deploy step fails — local dev still works |
| GitHub Actions repo secrets (if any added) | Per-secret tool | Repo → Settings → Secrets → Actions | Affected workflow fails |

**Rotation order during a confirmed compromise**: session secrets first (immediate cookie kill), then API keys (kills new auth), then deploy tokens (kills attacker's deploy pipeline last so legitimate deploys keep working while you fix).

**Each rotation MUST be logged** in `docs/security/rotation-log.md` (create this file on first rotation; not pre-created today to avoid empty scaffolding). Log row: date, secret name, reason (scheduled / suspected leak / confirmed compromise), performed by, verification command run.

---

## 7. Out of band recovery contacts

Keep these accessible without depending on MedRash infrastructure (printed copy + offline password manager entry):

- Supabase support: see [vendor-register.md](vendor-register.md)
- Netlify support: see [vendor-register.md](vendor-register.md)
- Domain registrar support: TBD (add registrar name + 24/7 abuse line before pilot launch)
- GitHub support: https://support.github.com
- Cloudflare support (for Turnstile): https://dash.cloudflare.com/?to=/:account/support
- Primary on-call: see [incident-response.md §2](incident-response.md#2-on-call)

---

## 8. Standards mapping

- ISO 27001 §A.17 (information security aspects of business continuity)
- ISO 27002 §8.13 (information backup), §8.14 (redundancy of information processing facilities)
- NIST CSF RC.RP (recovery planning), RC.IM (improvements)
- SOC 2 A1.2 (availability), A1.3 (recovery)
- GDPR Art. 32 §1(c) ("ability to restore the availability and access to personal data in a timely manner")
