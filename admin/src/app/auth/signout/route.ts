import { NextResponse, type NextRequest } from "next/server";

import { getServerSupabaseClient } from "@/lib/supabase-ssr";

export const dynamic = "force-dynamic";

async function signOutAndBounce(request: NextRequest) {
  const supabase = await getServerSupabaseClient();
  await supabase.auth.signOut();
  return NextResponse.redirect(new URL("/login", request.url));
}

export async function POST(request: NextRequest) {
  return signOutAndBounce(request);
}

export async function GET(request: NextRequest) {
  // GET fallback so a plain anchor tag works if JS is disabled.
  return signOutAndBounce(request);
}
