/**
 * P0.9 — CSP violation collector.
 *
 * Modern browsers POST CSP reports here (configured via the `report-uri`
 * and `report-to` directives in admin/next.config.ts). We log to the
 * server console so operators see what the policy is blocking when they
 * tighten directives or before flipping from report-only to enforce.
 *
 * Two payload shapes are supported:
 *   - Legacy `report-uri`:   { "csp-report": { ...fields } }
 *     Content-Type: application/csp-report
 *   - Modern  `report-to`:   [ { type: "csp-violation", body: {...} }, ... ]
 *     Content-Type: application/reports+json
 *
 * The endpoint always returns 204 — telling browsers to retry is pointless
 * for diagnostic reports.
 */

import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type CspReport = {
  "document-uri"?: string;
  "violated-directive"?: string;
  "effective-directive"?: string;
  "blocked-uri"?: string;
  "source-file"?: string;
  "line-number"?: number;
  "status-code"?: number;
};

type ReportingApiEntry = {
  type?: string;
  url?: string;
  body?: Record<string, unknown>;
};

function summarize(report: CspReport): string {
  const directive =
    report["effective-directive"] ?? report["violated-directive"] ?? "?";
  const blocked = report["blocked-uri"] ?? "(none)";
  const doc = report["document-uri"] ?? "?";
  return `directive=${directive} blocked=${blocked} doc=${doc}`;
}

export async function POST(request: Request): Promise<Response> {
  let parsed: unknown;
  try {
    parsed = await request.json();
  } catch {
    return new NextResponse(null, { status: 204 });
  }

  if (
    parsed &&
    typeof parsed === "object" &&
    "csp-report" in (parsed as Record<string, unknown>)
  ) {
    const report = (parsed as { "csp-report"?: CspReport })["csp-report"];
    if (report) {
      console.warn(`[csp-report] ${summarize(report)}`);
    }
  } else if (Array.isArray(parsed)) {
    for (const entry of parsed as ReportingApiEntry[]) {
      if (entry?.type === "csp-violation" && entry.body) {
        console.warn(`[csp-report] ${summarize(entry.body as CspReport)}`);
      }
    }
  }

  return new NextResponse(null, { status: 204 });
}

// Some browsers send an OPTIONS preflight for cross-origin reports; the
// admin-only origin keeps reports same-origin in practice but accept it
// defensively so a stray preflight doesn't surface as a 405 in the logs.
export async function OPTIONS(): Promise<Response> {
  return new NextResponse(null, { status: 204 });
}
