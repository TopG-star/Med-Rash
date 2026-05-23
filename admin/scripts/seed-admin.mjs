#!/usr/bin/env node
// admin/scripts/seed-admin.mjs
//
// Bootstraps the first superadmin (or upgrades an existing admin to
// superadmin) on a fresh Supabase project. Uses the Supabase Admin API,
// not raw SQL on auth.users.
//
// Usage (must run from the admin/ directory so Node resolves
// @supabase/supabase-js from admin/node_modules):
//   cd admin
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   ADMIN_BOOTSTRAP_EMAIL=you@example.com \
//   node ./scripts/seed-admin.mjs

import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL?.trim();
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const email = process.env.ADMIN_BOOTSTRAP_EMAIL?.trim();

if (!url || !serviceRoleKey) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  process.exit(1);
}
if (!email) {
  console.error("ADMIN_BOOTSTRAP_EMAIL is required.");
  process.exit(1);
}

const supabase = createClient(url, serviceRoleKey, {
  db: { schema: "app" },
  auth: { autoRefreshToken: false, persistSession: false },
});

async function findAuthUserByEmail(targetEmail) {
  // listUsers is paginated; first 1000 is more than enough for pilot.
  const { data, error } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (error) throw new Error(`listUsers failed: ${error.message}`);
  const lower = targetEmail.toLowerCase();
  return data.users.find((u) => (u.email ?? "").toLowerCase() === lower) ?? null;
}

async function main() {
  console.log(`[seed-admin] bootstrap email: ${email}`);

  let authUser = await findAuthUserByEmail(email);
  if (!authUser) {
    console.log("[seed-admin] inviting via auth.admin.inviteUserByEmail …");
    const { data, error } = await supabase.auth.admin.inviteUserByEmail(email);
    if (error) throw new Error(`inviteUserByEmail failed: ${error.message}`);
    authUser = data.user;
  } else {
    console.log(`[seed-admin] auth user already exists (${authUser.id})`);
  }

  const { error: upsertError } = await supabase
    .from("admin_users")
    .upsert(
      {
        user_id: authUser.id,
        email,
        role: "superadmin",
        is_active: true,
        invited_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );

  if (upsertError) {
    throw new Error(`admin_users upsert failed: ${upsertError.message}`);
  }

  console.log("[seed-admin] OK");
  console.log(`  user_id : ${authUser.id}`);
  console.log(`  email   : ${email}`);
  console.log(`  role    : superadmin`);
  console.log(`  active  : true`);
  console.log("");
  console.log("Sign in by visiting /login and requesting a magic link to this address.");
}

main().catch((err) => {
  console.error("[seed-admin] FAILED:", err.message);
  process.exit(2);
});
