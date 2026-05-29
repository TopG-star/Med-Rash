# MedRash Incident Response Runbook

> Slice B5 of [`security-hardening-plan.md`](../security-hardening-plan.md). Operating procedure for any security or availability incident.

**Last reviewed**: 2025-01 (initial draft).
**Owner**: Product (single-person on-call today; designed for rotation expansion).

---

## 1. Severity matrix

| SEV | Definition | Examples | Acknowledge SLA | Resolve SLA | Comms |
|---|---|---|---|---|---|
| **SEV1** | Confirmed personal-data breach OR total outage of admin or participant surface OR confirmed unauthorised owner-role access | RLS bypass found in production; admin allowlist defeated; database export observed in audit log; full Netlify down >15 min | 15 min | 4 h to mitigation, 24 h to full fix | Internal: immediate · External: per §4 GDPR · Status page if multi-tenant |
| **SEV2** | Degraded privileged surface, no confirmed data loss | Login MFA failing for some users; live session UI degraded; audit log write lag >5 min; single-tenant data corruption | 1 h | 24 h | Internal: same day · Affected tenants only |
| **SEV3** | Single-tenant impact OR confirmed near-miss with no exposure | One school's leaderboard stale; one admin can't sign in due to misconfig; intel signal of vendor compromise without confirmed exploitation | 1 business day | 5 business days | Affected tenant directly |
| **SEV4** | Low-impact issue or hardening opportunity surfaced by an alert | Audit log retention nearing 95%; weak password reuse warning; advisory CVE in non-runtime dep | Next business day | Sprint cadence | Ticket only |

---

## 2. On-call

**Today (single-person)**:

- Primary: Product owner (you).
- Acknowledgement contact: monitored email + phone (documented in Netlify env: `INCIDENT_PRIMARY_EMAIL`, `INCIDENT_PRIMARY_PHONE`). Do **not** commit values; set in Netlify env only.
- **Single-point-of-failure callout**: if primary fails to acknowledge within the SLA, the automatic fallback is to escalate to vendor support (Supabase Pro support + Netlify support) AND switch the affected surface to read-only mode (see §5.2). Until a co-on-call exists, "self-DoS by holiday" is an accepted residual risk recorded in the [Decisions Log](../security-hardening-plan.md#8-decisions-log).

**Designed for future rotation**:

- Roles are defined here so adding a second/third on-call is a config change, not a runbook rewrite.
- **Incident Commander (IC)**: owns the bridge, makes go/no-go calls, files the post-mortem. Default = on-call primary.
- **Communications Lead**: handles internal + external messaging. Default = IC until a second person is on-call.
- **Scribe**: timestamps every action in the incident ticket. Default = IC until a third person is on-call.
- **Subject-matter expert (SME)**: rotates in by surface (admin-auth, participant, host-live, recovery, leaderboard) — today all SME roles collapse onto the single on-call.

When a second person joins the rotation: split IC + Comms; update this file; update `INCIDENT_*` env vars; add a hand-off section.

---

## 3. Detection → triage → response → recovery

### 3.1 Detection sources

- **Push**: Supabase log alert (RLS denials, OTP rate-limit spikes), Netlify deploy/build failure email, Sentry (if/when wired), participant or admin user report.
- **Pull**: weekly audit log review (planned slice B8), monthly Supabase Advisor lints.

### 3.2 Triage (15 min target for SEV1/SEV2)

1. Open a new incident ticket: `INC-YYYYMMDD-NN` (template at `docs/security/templates/INCIDENT.md` — to be added when first incident files; until then use a fresh GitHub issue with label `incident`).
2. Confirm severity using §1 table — when in doubt, **upgrade** one tier.
3. Identify the affected surface and pull the matching [threat-model one-pager](threat-model/) for the known controls and residual risk.
4. Decide containment strategy (see §5).

### 3.3 Response

1. Apply containment from §5 (read-only mode, secret rotation, allowlist tightening).
2. Capture evidence: download relevant audit log slice, take Supabase metrics screenshot, capture Netlify deploy log.
3. Coordinate fix via standard PR + verification flow — security hardening rules in [security-hardening-plan.md](../security-hardening-plan.md) still apply (no `--no-verify`, no destructive shortcuts).
4. Communicate per §4.

### 3.4 Recovery

1. Verify fix in a hosted dry-run.
2. Re-enable normal traffic.
3. Schedule the post-mortem (§6) within 7 days for SEV1/SEV2.

---

## 4. External communications & GDPR

MedRash pilot includes **both EU/EEA and non-EU participants**. EU obligations are the primary bar; non-EU notification follows the stricter of (a) local law where applicable and (b) the EU template, voluntarily.

### 4.1 GDPR 72-hour rule

A confirmed **personal data breach** affecting EU data subjects triggers a notification to the lead supervisory authority within **72 hours** of becoming aware (GDPR Art. 33). If the breach is likely to result in high risk to data subjects, also notify the data subjects without undue delay (Art. 34).

### 4.2 Breach notification template (Art. 33 §3 + Art. 34 §2)

```
Subject: MedRash personal data breach notification — INC-YYYYMMDD-NN

1. Nature of the breach: [description]
2. Categories and approximate number of data subjects: [e.g. ~N pilot participants]
3. Categories and approximate number of records: [e.g. ~N attempt records, ~N email addresses]
4. Likely consequences: [e.g. account enumeration, no financial data exposed]
5. Measures taken / proposed: [containment, fix, hardening]
6. Contact point: [DPO or owner contact]
7. Timeline:
   - Detected: [UTC timestamp]
   - Contained: [UTC timestamp]
   - Notification sent: [UTC timestamp]
```

### 4.3 Recipients

| Audience | When | Channel |
|---|---|---|
| Affected data subjects (EU) | Without undue delay if high risk | Email from `INCIDENT_PRIMARY_EMAIL`; localized if known |
| Affected data subjects (non-EU) | Voluntarily, same template | Same channel |
| Lead supervisory authority (EU) | Within 72 h of awareness | Member-state-specific portal (record portal URL per pilot region in `docs/security/dpa/` once filed) |
| Internal stakeholders | Immediately on SEV1, same day on SEV2 | Direct |
| Vendor partner (Supabase, Netlify, etc.) | If vendor surface is in the kill chain | Support portal — see [vendor-register.md](vendor-register.md) for contact rows |

### 4.4 If non-personal-data incident

Skip §4.1–§4.3. Internal comms only unless availability of a tenant-facing surface was degraded — then notify affected tenants directly.

---

## 5. Standard containment playbooks

### 5.1 Suspected stolen admin session

1. Rotate `MEDRASH_ADMIN_SESSION_SECRET` in Netlify env (this invalidates every signed admin session — see [admin-session-cookie.ts](../../admin/src/lib/admin-session-cookie.ts)).
2. In Supabase dashboard → Auth → Users, revoke refresh tokens for the affected user.
3. Force a Netlify redeploy so the new secret is live (sub-2 min).
4. Confirm via `audit_log` that the affected `userId` no longer has fresh `session_*` events.

### 5.2 Read-only mode for participant surface

1. Disable `attempt-submit` Netlify function in the Netlify dashboard (or push an env flag `MEDRASH_ATTEMPTS_READONLY=1` if implemented).
2. Leaderboard reads stay live.
3. Post a status note via in-app banner (if shipped) or out-of-band.

### 5.3 RLS bypass suspected

1. Disable the implicated server action route at the Netlify dashboard.
2. Revoke any service-role key that may have leaked: Supabase dashboard → Settings → API → Reset service role.
3. Pull recent audit log entries for the affected table.

### 5.4 Recovery flow abused (account takeover attempts)

1. Tighten `recover-request` rate limit (env var `RECOVER_RATE_LIMIT_PER_HOUR`) — see [participant-runner.md](threat-model/recovery.md).
2. If a specific owner is being targeted, switch their recovery to **manual** mode (next §5.5).

### 5.5 Runbook: owner account lockout (no co-owner)

1. **Verify identity out-of-band**: video call + government ID match against on-file record.
2. **Block self-serve**: in Supabase dashboard, disable the user, then re-enable to invalidate any in-flight recovery OTPs.
3. **Restore allowlist**: insert/update `admin_users` row via Supabase SQL editor under service role.
4. **Rotate `MEDRASH_ADMIN_SESSION_SECRET`** (invalidates all current sessions — see §5.1).
5. **Re-enrol TOTP** (once B1 P2 ships): require the recovered owner to enrol from a clean device on first login.
6. **File post-incident review** (§6) within 7 days regardless of severity.

### 5.6 Vendor-side incident (Supabase / Netlify / etc.)

1. Check vendor status page (links in [vendor-register.md](vendor-register.md)).
2. Open a support ticket; record ticket ID in the incident log.
3. If MedRash data is in the kill chain, treat as SEV1 even if vendor calls it lower.

---

## 6. Post-incident

For SEV1 and SEV2:

1. Within 7 days, file a post-mortem covering:
   - Timeline (UTC, minute-level for SEV1, hour-level for SEV2)
   - Root cause (use the `rca` skill — fishbone + 5 whys)
   - What worked / what didn't
   - Corrective actions with owner + due date
2. Update the affected [threat-model one-pager](threat-model/) — at minimum bump `Last reviewed`; add residual risk rows if newly accepted.
3. If a control failed, add an action to the [security-hardening-plan.md](../security-hardening-plan.md) Decisions Log or sub-task list.

For SEV3/SEV4: ticket-level retrospective only.

---

## 7. Standards mapping

- ISO 27001 §A.16 (information security incident management)
- ISO 27002 §5.24–5.27 (incident management lifecycle)
- NIST CSF RS (Respond), RC (Recover)
- GDPR Art. 33 (breach notification to authority), Art. 34 (breach communication to data subjects)
