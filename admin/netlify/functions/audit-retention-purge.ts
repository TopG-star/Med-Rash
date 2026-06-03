// Slice A5 phase 3 (Pillar 6) — nightly audit retention purge.
//
// Deletes rows from app.auth_events and app.admin_audit whose expire_at
// has passed (default retention = 730 days from insert; set by migration
// 017_audit_logging_tables.sql).
//
// Scheduled via netlify.toml [functions."audit-retention-purge"] schedule
// = "17 3 * * *" — 03:17 UTC daily. Off-the-hour to avoid colliding with
// other cron jobs that prefer round times.
//
// pg_cron is NOT enabled in this Supabase project, so this function is
// the canonical retention mechanism. If pg_cron is enabled in a future
// migration the function should be deleted, not run in parallel — having
// two cleanup paths is worse than one.
//
// Auth: scheduled functions are invoked by Netlify infrastructure with
// no exposed URL secret. They CAN also be POSTed manually; that's
// intentionally tolerated because the function is idempotent (only
// deletes already-expired rows) and requires the service-role key from
// env to do anything destructive.

import { getSupabaseAdminClient } from "./_shared/supabase";

type PurgeOutcome = {
  ok: boolean;
  purgedAt: string;
  authEventsDeleted: number;
  adminAuditDeleted: number;
  idempotencyKeysDeleted: number;
  errors: string[];
};

export default async (_req: Request): Promise<Response> => {
  const supabase = getSupabaseAdminClient();
  const purgedAt = new Date().toISOString();

  const errors: string[] = [];

  const { count: authEventsDeleted, error: authErr } = await supabase
    .from("auth_events")
    .delete({ count: "exact" })
    .lte("expire_at", purgedAt);
  if (authErr) errors.push(`auth_events: ${authErr.message}`);

  const { count: adminAuditDeleted, error: auditErr } = await supabase
    .from("admin_audit")
    .delete({ count: "exact" })
    .lte("expire_at", purgedAt);
  if (auditErr) errors.push(`admin_audit: ${auditErr.message}`);

  // P0.2 \u2014 idempotency cache rows expire after 24h (migration 019). Same
  // purge cadence keeps the table small without a separate cron.
  const { count: idempotencyKeysDeleted, error: idemErr } = await supabase
    .from("idempotency_keys")
    .delete({ count: "exact" })
    .lte("expire_at", purgedAt);
  if (idemErr) errors.push(`idempotency_keys: ${idemErr.message}`);

  const payload: PurgeOutcome = {
    ok: errors.length === 0,
    purgedAt,
    authEventsDeleted: authEventsDeleted ?? 0,
    adminAuditDeleted: adminAuditDeleted ?? 0,
    idempotencyKeysDeleted: idempotencyKeysDeleted ?? 0,
    errors,
  };

  if (!payload.ok) {
    console.error("[audit-retention-purge] failed", payload);
    return new Response(JSON.stringify(payload), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  console.log("[audit-retention-purge] ok", payload);
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
};
