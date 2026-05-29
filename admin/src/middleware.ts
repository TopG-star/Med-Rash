import { NextResponse, type NextRequest } from "next/server";

import {
  ADMIN_SESSION_ABSOLUTE_MS,
  ADMIN_SESSION_COOKIE_NAME,
  decideAdminSession,
  signAdminSessionCookie,
  verifyAdminSessionCookie,
} from "@/lib/admin-session-cookie";
import { getMiddlewareSupabaseClient } from "@/lib/supabase-ssr";

const PUBLIC_PATHS = new Set<string>([
  "/login",
  "/auth/callback",
  "/auth/signout",
  "/denied",
]);

function isPublic(pathname: string): boolean {
  if (PUBLIC_PATHS.has(pathname)) return true;
  if (pathname.startsWith("/_next/")) return true;
  if (pathname.startsWith("/api/")) return true;
  return false;
}

function buildExpireRedirect(
  request: NextRequest,
  reason: "idle" | "absolute",
): NextResponse {
  const loginUrl = new URL("/login", request.url);
  loginUrl.searchParams.set("reason", `session_${reason}`);
  const res = NextResponse.redirect(loginUrl);
  res.cookies.set({
    name: ADMIN_SESSION_COOKIE_NAME,
    value: "",
    path: "/",
    maxAge: 0,
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });
  // Evict Supabase auth cookies so the next /login load starts clean.
  // Names follow @supabase/ssr's `sb-<projectRef>-auth-token` convention;
  // iterate rather than hard-coding the project ref.
  for (const cookie of request.cookies.getAll()) {
    if (cookie.name.startsWith("sb-") && cookie.name.endsWith("-auth-token")) {
      res.cookies.set({
        name: cookie.name,
        value: "",
        path: "/",
        maxAge: 0,
        httpOnly: true,
        sameSite: "lax",
        secure: process.env.NODE_ENV === "production",
      });
    }
  }
  return res;
}

/**
 * Admin portal auth gate.
 *
 * Refreshes the Supabase session on every request, bounces unauthenticated
 * requests to /login?next=<originalPath>, and lets authenticated requests
 * through to the page (where requireAdminSession enforces the allowlist).
 *
 * Slice B1 phase 1: also enforces the session timeout policy (idle 30 min
 * + absolute 8 h) via a Web-Crypto-signed cookie (`medrash-admin-session`).
 * On timeout, clears both our own cookie and the Supabase auth cookies,
 * then redirects to /login?reason=session_idle | session_absolute.
 * The /login page emits the audit event from the Node runtime (Phase 3).
 */
export async function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const response = NextResponse.next({ request });

  if (isPublic(pathname)) {
    return response;
  }

  let user: { id: string } | null = null;
  try {
    const supabase = getMiddlewareSupabaseClient(request, response);
    const { data } = await supabase.auth.getUser();
    user = data.user ? { id: data.user.id } : null;
  } catch (err) {
    console.error("[middleware] supabase init failed", err);
    return NextResponse.redirect(new URL("/denied?reason=config", request.url));
  }

  if (!user) {
    const next = `${pathname}${search ?? ""}`;
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("next", next);
    return NextResponse.redirect(loginUrl);
  }

  const cookieRaw = request.cookies.get(ADMIN_SESSION_COOKIE_NAME)?.value ?? null;
  const verifyResult = await verifyAdminSessionCookie(cookieRaw);
  const claims = verifyResult.ok ? verifyResult.claims : null;
  const nowMs = Date.now();
  const decision = decideAdminSession({
    claims,
    currentUserId: user.id,
    nowMs,
  });

  if (decision.action === "expire") {
    return buildExpireRedirect(request, decision.reason);
  }

  const authedAtSec =
    decision.action === "init" ? Math.floor(nowMs / 1000) : claims!.authedAt;
  const lastSeenAtSec = Math.floor(nowMs / 1000);

  let signedCookie: string;
  try {
    signedCookie = await signAdminSessionCookie({
      userId: user.id,
      authedAt: authedAtSec,
      lastSeenAt: lastSeenAtSec,
    });
  } catch (err) {
    // Secret missing or unsignable — fail closed (same posture as the
    // Supabase init-failure branch above) rather than letting the request
    // through without a session-timeout cookie.
    console.error("[middleware] admin-session cookie sign failed", err);
    return NextResponse.redirect(new URL("/denied?reason=config", request.url));
  }
  response.cookies.set({
    name: ADMIN_SESSION_COOKIE_NAME,
    value: signedCookie,
    path: "/",
    maxAge: Math.floor(ADMIN_SESSION_ABSOLUTE_MS / 1000),
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });

  return response;
}

export const config = {
  matcher: [
    // Exclude Next.js internals, static assets, AND /.netlify/* so that
    // Netlify Functions (e.g. /.netlify/functions/session-resolve called
    // by the Flutter participant app) are dispatched by Netlify's edge
    // BEFORE Next.js middleware runs. Without the /.netlify/ exclusion,
    // unauthenticated function calls get 307-redirected to /login,
    // breaking every cross-origin participant API call.
    "/((?!_next/static|_next/image|favicon.ico|\\.netlify/|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
