import "server-only";

import { createClient } from "@supabase/supabase-js";

type AdminSupabaseClient = ReturnType<typeof buildAdminClient>;

let cachedAdminClient: AdminSupabaseClient | null = null;

function buildAdminClient(url: string, serviceRoleKey: string) {
  return createClient(url, serviceRoleKey, {
    db: { schema: "app" },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Lazy-singleton Supabase client scoped to the `app` schema, authenticated with
 * the service-role key. SERVER-ONLY — never import from a Client Component or
 * any file shipped to the browser bundle.
 */
export function getAdminSupabaseClient(): AdminSupabaseClient {
  if (cachedAdminClient) {
    return cachedAdminClient;
  }

  const url = process.env.SUPABASE_URL?.trim();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

  if (!url || !serviceRoleKey) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be configured for the admin app.",
    );
  }

  cachedAdminClient = buildAdminClient(url, serviceRoleKey);
  return cachedAdminClient;
}
