// Phase 1 (P1.4) — daily KPI digest for managers.
//
// Scheduled at 08:00 UTC daily (08:00 UTC == 08:00 GMT == 04:00 EST /
// 13:00 IST etc.; close to "start of business" for the West Africa
// pilot). The function:
//
//   1. Aggregates per-session KPIs for "yesterday" via
//      `app.session_kpis_for_date(p_date)` (migration 020).
//   2. Builds a Slack-shaped JSON payload that summarises the day.
//   3. POSTs the payload to `MEDRASH_KPI_DIGEST_WEBHOOK_URL` if set.
//      Otherwise logs and exits 200 — the function is still useful as
//      a no-op heartbeat that proves the aggregate query works.
//
// Design notes:
//   * "Yesterday" is computed in UTC, not in the operator's local zone.
//     For the pilot this is acceptable; revisit if managers complain
//     about the cutover landing mid-event.
//   * The webhook payload is generic Slack `blocks` so any Slack-style
//     receiver (Slack, Mattermost, Discord webhook with shim, Zapier)
//     can consume it. To change shape, edit `buildDigestBlocks`.
//   * Authentication on the outbound webhook is by URL secret only —
//     Slack incoming-webhook URLs already carry the credential in the
//     path. Treat `MEDRASH_KPI_DIGEST_WEBHOOK_URL` as a secret in
//     Netlify env.

import { getSupabaseAdminClient } from "./_shared/supabase";
import { getOrMintRequestId } from "../../src/lib/request-id";

type SessionKpiRow = {
  session_id: string;
  session_name: string | null;
  quiz_id: string | null;
  quiz_title: string | null;
  join_count: number;
  completed_count: number;
  completion_rate: number;
  average_score: number | null;
  median_time_seconds: number | null;
};

type DigestOutcome = {
  ok: boolean;
  requestId: string;
  forDate: string;
  sessions: number;
  totalJoins: number;
  totalCompleted: number;
  webhookSent: boolean;
  errors: string[];
};

function yesterdayUtc(now: Date = new Date()): string {
  const d = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

function formatScore(n: number | null): string {
  return n === null || Number.isNaN(n) ? "—" : n.toFixed(1);
}

function formatSeconds(n: number | null): string {
  if (n === null || Number.isNaN(n)) return "—";
  if (n < 60) return `${n.toFixed(0)}s`;
  const m = Math.floor(n / 60);
  const s = Math.round(n - m * 60);
  return `${m}m${s.toString().padStart(2, "0")}s`;
}

function buildDigestBlocks(
  forDate: string,
  rows: SessionKpiRow[],
): { text: string; blocks: unknown[] } {
  const totalJoins = rows.reduce((acc, r) => acc + r.join_count, 0);
  const totalCompleted = rows.reduce((acc, r) => acc + r.completed_count, 0);
  const overallCompletion =
    totalJoins === 0 ? 0 : Math.round((totalCompleted / totalJoins) * 1000) / 10;

  const headerText = `MedRash daily KPI digest — ${forDate}`;
  const summaryLine =
    rows.length === 0
      ? "_No session activity yesterday._"
      : `*${rows.length}* session${rows.length === 1 ? "" : "s"} · ` +
        `*${totalJoins}* joins · *${totalCompleted}* completed · ` +
        `*${overallCompletion}%* completion`;

  const sessionLines = rows.slice(0, 10).map((r) => {
    const name = r.session_name ?? "(unnamed session)";
    const quiz = r.quiz_title ?? "—";
    return (
      `• *${name}* (${quiz})\n` +
      `   joins ${r.join_count} · completed ${r.completed_count} · ` +
      `rate ${r.completion_rate.toFixed(0)}% · ` +
      `avg ${formatScore(r.average_score)} · ` +
      `median ${formatSeconds(r.median_time_seconds)}`
    );
  });

  const blocks: unknown[] = [
    {
      type: "header",
      text: { type: "plain_text", text: headerText },
    },
    {
      type: "section",
      text: { type: "mrkdwn", text: summaryLine },
    },
  ];
  if (sessionLines.length > 0) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: sessionLines.join("\n") },
    });
  }
  if (rows.length > 10) {
    blocks.push({
      type: "context",
      elements: [
        {
          type: "mrkdwn",
          text: `_+${rows.length - 10} more sessions; see /reports for the full breakdown._`,
        },
      ],
    });
  }

  return { text: headerText, blocks };
}

export default async (req: Request): Promise<Response> => {
  const requestId = getOrMintRequestId(req.headers);
  const forDate = yesterdayUtc();
  const errors: string[] = [];

  let rows: SessionKpiRow[] = [];
  try {
    const supabase = getSupabaseAdminClient();
    const { data, error } = await supabase.rpc("session_kpis_for_date", {
      p_date: forDate,
    });
    if (error) {
      errors.push(`session_kpis_for_date: ${error.message}`);
    } else if (Array.isArray(data)) {
      rows = data as SessionKpiRow[];
    }
  } catch (err) {
    errors.push(
      `aggregate query threw: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  const totalJoins = rows.reduce((acc, r) => acc + r.join_count, 0);
  const totalCompleted = rows.reduce((acc, r) => acc + r.completed_count, 0);

  const webhookUrl = process.env.MEDRASH_KPI_DIGEST_WEBHOOK_URL;
  let webhookSent = false;
  if (webhookUrl) {
    const payload = buildDigestBlocks(forDate, rows);
    try {
      const res = await fetch(webhookUrl, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-request-id": requestId,
        },
        body: JSON.stringify(payload),
      });
      if (!res.ok) {
        errors.push(`webhook POST returned ${res.status}`);
      } else {
        webhookSent = true;
      }
    } catch (err) {
      errors.push(
        `webhook POST threw: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  const outcome: DigestOutcome = {
    ok: errors.length === 0,
    requestId,
    forDate,
    sessions: rows.length,
    totalJoins,
    totalCompleted,
    webhookSent,
    errors,
  };

  if (!outcome.ok) {
    console.error("[kpi-digest] failed", outcome);
    return new Response(JSON.stringify(outcome), {
      status: 500,
      headers: { "content-type": "application/json", "x-request-id": requestId },
    });
  }

  console.log("[kpi-digest] ok", outcome);
  return new Response(JSON.stringify(outcome), {
    status: 200,
    headers: { "content-type": "application/json", "x-request-id": requestId },
  });
};
