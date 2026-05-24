import { NextResponse, type NextRequest } from "next/server";

import { getServerSupabaseClient } from "@/lib/supabase-ssr";

import {
  handleAuthCallbackGet,
  handleAuthCallbackPost,
  type CallbackSupabase,
} from "./callback-handler";

export const dynamic = "force-dynamic";

function safeNext(raw: string | null | undefined): string {
  return raw && raw.startsWith("/") ? raw : "/dashboard";
}

/**
 * Supabase post-verify callback. Two arrival modes:
 *   - PKCE: provider redirects with `?code=...` -> exchange server-side.
 *   - Hash: provider redirects with `#access_token=...&refresh_token=...`
 *           (older implicit flow). Browsers do not send the hash to the
 *           server, so we render an interstitial that reads it and POSTs
 *           the tokens back.
 * Either way, the handler signs out any prior cookie session FIRST so a
 * visitor opening this URL in a browser already signed in as someone else
 * does not see that other user's data.
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const next = safeNext(url.searchParams.get("next"));

  const supabase = (await getServerSupabaseClient()) as unknown as CallbackSupabase;
  const result = await handleAuthCallbackGet({ supabase, code });

  if ("needsHashFlow" in result) {
    return new NextResponse(renderHashInterstitial(next), {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8" },
    });
  }

  if (!result.ok) {
    console.error("[auth/callback] GET failed", result);
    const denied = new URL("/denied", request.url);
    denied.searchParams.set("reason", result.reason);
    return NextResponse.redirect(denied);
  }

  return NextResponse.redirect(new URL(next, request.url));
}

/**
 * Hash-flow handoff. The interstitial POSTs the access/refresh tokens it
 * recovered from window.location.hash. We sign out any prior session and
 * call setSession() to persist the new one as cookies.
 */
export async function POST(request: NextRequest) {
  let payload: { access_token?: unknown; refresh_token?: unknown; next?: unknown };
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return NextResponse.json(
      { ok: false, reason: "bad_json" },
      { status: 400 },
    );
  }

  const accessToken =
    typeof payload.access_token === "string" ? payload.access_token : null;
  const refreshToken =
    typeof payload.refresh_token === "string" ? payload.refresh_token : null;
  const next = safeNext(typeof payload.next === "string" ? payload.next : null);

  const supabase = (await getServerSupabaseClient()) as unknown as CallbackSupabase;
  const result = await handleAuthCallbackPost({
    supabase,
    accessToken,
    refreshToken,
  });

  if ("needsHashFlow" in result) {
    return NextResponse.json(
      { ok: false, reason: "no_code_no_hash" },
      { status: 400 },
    );
  }
  if (!result.ok) {
    console.error("[auth/callback] POST failed", result);
    return NextResponse.json(
      { ok: false, reason: result.reason, message: result.message ?? null },
      { status: 400 },
    );
  }

  return NextResponse.json({ ok: true, next });
}

/**
 * Self-contained HTML interstitial that runs in the invitee's browser,
 * reads tokens from the URL hash, and posts them to this same route. On
 * success it navigates to `next`; on failure it forwards to /denied so the
 * user is never silently dropped on a stale dashboard.
 */
function renderHashInterstitial(next: string): string {
  // `next` is already constrained to start with "/" by safeNext, so it is
  // safe to embed as a JSON string literal.
  const nextJson = JSON.stringify(next);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Signing you in…</title>
  <meta name="robots" content="noindex" />
  <style>
    html,body{height:100%;margin:0;font-family:system-ui,sans-serif;background:#fbf7ee;color:#1b1b1b}
    main{display:flex;align-items:center;justify-content:center;height:100%;flex-direction:column;gap:12px}
    p{margin:0;font-size:14px}
    .spinner{width:28px;height:28px;border:3px solid #1b1b1b;border-top-color:transparent;border-radius:50%;animation:spin .8s linear infinite}
    @keyframes spin{to{transform:rotate(360deg)}}
  </style>
</head>
<body>
  <main>
    <div class="spinner" aria-hidden="true"></div>
    <p id="msg">Signing you in…</p>
  </main>
  <script>
    (function () {
      var next = ${nextJson};
      var hash = window.location.hash || "";
      if (hash.charAt(0) === "#") hash = hash.slice(1);
      var params = new URLSearchParams(hash);
      var at = params.get("access_token");
      var rt = params.get("refresh_token");

      function deny(reason) {
        window.location.replace("/denied?reason=" + encodeURIComponent(reason));
      }

      if (!at || !rt) {
        deny("callback_no_code");
        return;
      }

      fetch("/auth/callback", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ access_token: at, refresh_token: rt, next: next })
      })
        .then(function (r) { return r.json().then(function (j) { return { status: r.status, body: j }; }); })
        .then(function (res) {
          if (res.status === 200 && res.body && res.body.ok) {
            window.location.replace(res.body.next || next);
          } else {
            deny((res.body && res.body.reason) || "set_session");
          }
        })
        .catch(function () { deny("set_session"); });
    })();
  </script>
</body>
</html>`;
}
