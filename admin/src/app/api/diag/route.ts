import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * TEMPORARY diagnostic route — Phase 5 hosted env verification.
 * Prints byte-level info about server env vars WITHOUT exposing secrets.
 * Remove this file once hosted deploy is green.
 *
 * GET /api/diag
 */
export async function GET() {
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const gateKey = process.env.MEDRASH_GATE_API_KEY;
  const writeKey = process.env.MEDRASH_ADMIN_WRITE_KEY;
  const appBase = process.env.MEDRASH_APP_PUBLIC_BASE_URL;

  const report: Record<string, unknown> = {
    runtime: "nodejs",
    nodeVersion: process.version,
    timestamp: new Date().toISOString(),
  };

  report.SUPABASE_URL = describeUrl(url);
  report.SUPABASE_SERVICE_ROLE_KEY = describeSecret(serviceKey, "eyJ");
  report.MEDRASH_GATE_API_KEY = describeSecret(gateKey, null);
  report.MEDRASH_ADMIN_WRITE_KEY = describeSecret(writeKey, null);
  report.MEDRASH_APP_PUBLIC_BASE_URL = describeUrl(appBase);

  report.liveSupabaseProbe = await probeSupabase(url, serviceKey);

  return NextResponse.json(report, {
    headers: { "Cache-Control": "no-store" },
  });
}

function describeUrl(raw: string | undefined) {
  if (raw === undefined) {
    return { present: false };
  }
  const trimmed = raw.trim();
  const charCodes: Record<string, number> = {};
  for (let i = 0; i < Math.min(3, raw.length); i++) {
    charCodes[`pos${i}`] = raw.charCodeAt(i);
  }
  for (let i = Math.max(0, raw.length - 3); i < raw.length; i++) {
    charCodes[`pos${i}`] = raw.charCodeAt(i);
  }
  let urlParseOk = false;
  let urlParseError: string | null = null;
  let parsedHost: string | null = null;
  let parsedPath: string | null = null;
  try {
    const u = new URL(trimmed);
    urlParseOk = true;
    parsedHost = u.host;
    parsedPath = u.pathname;
  } catch (err) {
    urlParseError = err instanceof Error ? err.message : String(err);
  }
  return {
    present: true,
    rawLength: raw.length,
    trimmedLength: trimmed.length,
    hasLeadingWhitespace: raw.length !== raw.trimStart().length,
    hasTrailingWhitespace: raw.length !== raw.trimEnd().length,
    hasTrailingSlash: trimmed.endsWith("/"),
    startsWithHttps: trimmed.startsWith("https://"),
    endsWithSupabaseCo: trimmed.endsWith(".supabase.co"),
    first30: trimmed.slice(0, 30),
    last10: trimmed.slice(-10),
    charCodes,
    urlParseOk,
    urlParseError,
    parsedHost,
    parsedPath,
  };
}

function describeSecret(raw: string | undefined, expectedPrefix: string | null) {
  if (raw === undefined) {
    return { present: false };
  }
  const trimmed = raw.trim();
  return {
    present: true,
    rawLength: raw.length,
    trimmedLength: trimmed.length,
    hasLeadingWhitespace: raw.length !== raw.trimStart().length,
    hasTrailingWhitespace: raw.length !== raw.trimEnd().length,
    first4: trimmed.slice(0, 4),
    last4: trimmed.slice(-4),
    prefixOk: expectedPrefix === null ? null : trimmed.startsWith(expectedPrefix),
  };
}

async function probeSupabase(
  url: string | undefined,
  serviceKey: string | undefined,
) {
  if (!url || !serviceKey) {
    return { skipped: true, reason: "Missing SUPABASE_URL or service key." };
  }
  const trimmedUrl = url.trim().replace(/\/+$/, "");
  const trimmedKey = serviceKey.trim();
  const target = `${trimmedUrl}/rest/v1/quizzes?select=id&limit=1`;

  const restProbe = await safeFetch(target, {
    method: "GET",
    headers: {
      apikey: trimmedKey,
      Authorization: `Bearer ${trimmedKey}`,
      "Accept-Profile": "app",
    },
  });

  let supabaseJsProbe: Record<string, unknown> = { skipped: true };
  try {
    const { createClient } = await import("@supabase/supabase-js");
    const client = createClient(trimmedUrl, trimmedKey, {
      db: { schema: "app" },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await client.from("quizzes").select("id").limit(1);
    supabaseJsProbe = {
      skipped: false,
      ok: error === null,
      errorMessage: error?.message ?? null,
      errorCode: error?.code ?? null,
      errorDetails: error?.details ?? null,
      errorHint: error?.hint ?? null,
      rowCount: Array.isArray(data) ? data.length : null,
    };
  } catch (err) {
    supabaseJsProbe = {
      skipped: false,
      ok: false,
      threw: err instanceof Error ? err.message : String(err),
    };
  }

  return { target, restProbe, supabaseJsProbe };
}

async function safeFetch(target: string, init: RequestInit) {
  try {
    const res = await fetch(target, init);
    let bodySnippet: string | null = null;
    try {
      bodySnippet = (await res.text()).slice(0, 200);
    } catch {
      bodySnippet = "<unreadable body>";
    }
    return {
      ok: res.ok,
      status: res.status,
      statusText: res.statusText,
      bodySnippet,
    };
  } catch (err) {
    return {
      ok: false,
      threw: err instanceof Error ? err.message : String(err),
    };
  }
}
