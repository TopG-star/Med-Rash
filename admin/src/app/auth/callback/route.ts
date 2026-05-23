import { NextResponse, type NextRequest } from "next/server";

import { getServerSupabaseClient } from "@/lib/supabase-ssr";

export const dynamic = "force-dynamic";

/**
 * Supabase magic-link callback. The provider redirects here with either a
 * `?code=...` (PKCE) or hash-fragment tokens. We exchange the code for a
 * session cookie and then forward to `?next=`.
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const nextRaw = url.searchParams.get("next");
  const next = nextRaw && nextRaw.startsWith("/") ? nextRaw : "/dashboard";

  if (!code) {
    // Hash-fragment flow: cookies were already set by the helper page;
    // just bounce to next.
    return NextResponse.redirect(new URL(next, request.url));
  }

  const supabase = await getServerSupabaseClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    console.error("[auth/callback] exchangeCodeForSession failed", error);
    const denied = new URL("/denied", request.url);
    denied.searchParams.set("reason", "exchange");
    return NextResponse.redirect(denied);
  }

  return NextResponse.redirect(new URL(next, request.url));
}
