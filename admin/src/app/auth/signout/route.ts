import { NextResponse, type NextRequest } from "next/server";

import { ADMIN_SESSION_COOKIE_NAME } from "@/lib/admin-session-cookie";
import { getServerSupabaseClient } from "@/lib/supabase-ssr";

export const dynamic = "force-dynamic";

async function signOutAndBounce(request: NextRequest) {
  const supabase = await getServerSupabaseClient();
  await supabase.auth.signOut();
  const response = NextResponse.redirect(new URL("/login", request.url));
  // Slice B1 phase 1 — clear the session-timeout cookie alongside the
  // Supabase session cookies so the next login starts a fresh window.
  response.cookies.set({
    name: ADMIN_SESSION_COOKIE_NAME,
    value: "",
    path: "/",
    maxAge: 0,
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });
  return response;
}

export async function POST(request: NextRequest) {
  return signOutAndBounce(request);
}

export async function GET(request: NextRequest) {
  // GET fallback so a plain anchor tag works if JS is disabled.
  return signOutAndBounce(request);
}
