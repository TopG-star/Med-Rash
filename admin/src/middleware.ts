import { NextResponse, type NextRequest } from "next/server";

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

/**
 * Admin portal auth gate.
 *
 * Refreshes the Supabase session on every request, bounces unauthenticated
 * requests to /login?next=<originalPath>, and lets authenticated requests
 * through to the page (where requireAdminSession enforces the allowlist).
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

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
