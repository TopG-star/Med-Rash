import "server-only";

import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { NextRequest, NextResponse } from "next/server";

function readEnv(name: string): string {
  const value = process.env[name] ?? process.env[`NEXT_PUBLIC_${name}`];
  if (!value || value.trim().length === 0) {
    throw new Error(`${name} (or NEXT_PUBLIC_${name}) is required`);
  }
  return value;
}

/**
 * Cookie-bound Supabase client for Server Components, Route Handlers, and
 * Server Actions. Uses the anon key + the user's session cookie so RLS is
 * applied as the signed-in user. NEVER use this for service-role writes;
 * use {@link import("./supabase-server").getAdminSupabaseClient} for those.
 */
export async function getServerSupabaseClient() {
  const cookieStore = await cookies();
  const url = readEnv("SUPABASE_URL");
  const anonKey = readEnv("SUPABASE_ANON_KEY");

  return createServerClient(url, anonKey, {
    db: { schema: "app" },
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(toSet) {
        for (const { name, value, options } of toSet) {
          try {
            cookieStore.set(name, value, options);
          } catch {
            // Server Components can't mutate cookies. The middleware
            // handles refresh, so it's safe to swallow here.
          }
        }
      },
    },
  });
}

/**
 * Middleware-scoped Supabase client. Reads the inbound request cookies and
 * writes refreshed session cookies onto the supplied response so the browser
 * gets the rotated tokens on the next round-trip.
 */
export function getMiddlewareSupabaseClient(
  request: NextRequest,
  response: NextResponse,
) {
  const url = readEnv("SUPABASE_URL");
  const anonKey = readEnv("SUPABASE_ANON_KEY");

  return createServerClient(url, anonKey, {
    db: { schema: "app" },
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(toSet) {
        for (const { name, value, options } of toSet) {
          setRequestAndResponseCookie(request, response, name, value, options);
        }
      },
    },
  });
}

function setRequestAndResponseCookie(
  request: NextRequest,
  response: NextResponse,
  name: string,
  value: string,
  options: CookieOptions,
): void {
  request.cookies.set({ name, value, ...options });
  response.cookies.set({ name, value, ...options });
}
