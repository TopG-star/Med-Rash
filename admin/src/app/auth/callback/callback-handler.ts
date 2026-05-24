import "server-only";

/**
 * Minimal Supabase auth surface the callback uses. Kept here (not imported
 * from @supabase/supabase-js) so the unit test can pass a hand-rolled fake
 * without dragging in the real client.
 */
export type CallbackSupabase = {
  auth: {
    signOut: () => Promise<{ error: { message: string } | null }>;
    exchangeCodeForSession: (
      code: string,
    ) => Promise<{
      data: { user: { id: string } | null } | null;
      error: { message: string } | null;
    }>;
    setSession: (input: {
      access_token: string;
      refresh_token: string;
    }) => Promise<{
      data: { user: { id: string } | null } | null;
      error: { message: string } | null;
    }>;
  };
};

export type AdminStatus = "invited" | "verified" | "active" | "deactivated";

/**
 * Narrow contract the route uses to read admin_users.status and to flip
 * `invited -> verified` after the very first successful sign-in. Kept as
 * an interface (not an import of the service client) so the unit tests
 * can drive the routing logic without touching Supabase.
 */
export type AdminLookup = {
  selectStatus: (
    userId: string,
  ) => Promise<
    | { ok: true; status: AdminStatus }
    | { ok: false; reason: "not_found" | "error" }
  >;
  markVerified: (userId: string) => Promise<{ ok: true } | { ok: false }>;
};

export type PostAuthDestination =
  | { kind: "redirect"; path: string }
  | { kind: "denied"; reason: "allowlist" | "inactive" | "config" };

export type CallbackOutcome =
  | { ok: true; userId: string | null }
  | { ok: false; reason: "exchange" | "set_session" | "no_code_no_hash"; message?: string }
  | { needsHashFlow: true };

/**
 * Handle the GET side of /auth/callback.
 *
 * Two arrival modes:
 *   - PKCE (?code=...): the requesting browser stored a `code_verifier`
 *     cookie when signInWithOtp was called. exchangeCodeForSession needs
 *     that cookie to succeed, so we MUST NOT signOut() first — doing so
 *     would wipe the verifier and break self-initiated magic-link login.
 *     exchangeCodeForSession atomically overwrites the session cookies
 *     with the new user's tokens, which is enough to displace any prior
 *     admin's session in the same browser.
 *   - Hash flow (server-side invites, older implicit grant): tokens live
 *     in window.location.hash and never reach the server. We signOut()
 *     here (safe: no code_verifier in play) so the visitor cannot see a
 *     stale dashboard while the interstitial runs, then return
 *     needsHashFlow so the route can render the recovery page.
 */
export async function handleAuthCallbackGet(args: {
  supabase: CallbackSupabase;
  code: string | null;
}): Promise<CallbackOutcome> {
  const { supabase, code } = args;

  if (code) {
    // PKCE path. Do NOT signOut first — it would clear the code_verifier
    // cookie and the exchange would fail. exchangeCodeForSession will
    // overwrite the session cookies with the new user's tokens, so the
    // "owner cookie present, invitee clicks link" scenario still resolves
    // to the invitee's session (the new cookies replace the old ones).
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      return { ok: false, reason: "exchange", message: error.message };
    }
    return { ok: true, userId: data?.user?.id ?? null };
  }

  // No code = hash flow (or a malformed arrival). Wipe any prior session
  // cookie before handing off to the interstitial so the visitor cannot
  // see a stale dashboard while the recovery JS runs. There is no
  // code_verifier in play for the hash flow, so signOut is safe here.
  await supabase.auth.signOut();
  return { needsHashFlow: true };
}

/**
 * Handle the POST side of /auth/callback used by the hash-flow interstitial.
 * Same invariant: signOut FIRST, then setSession.
 */
export async function handleAuthCallbackPost(args: {
  supabase: CallbackSupabase;
  accessToken: string | null;
  refreshToken: string | null;
}): Promise<CallbackOutcome> {
  const { supabase, accessToken, refreshToken } = args;

  if (!accessToken || !refreshToken) {
    return { ok: false, reason: "no_code_no_hash" };
  }

  await supabase.auth.signOut();

  const { data, error } = await supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken,
  });
  if (error) {
    return { ok: false, reason: "set_session", message: error.message };
  }
  return { ok: true, userId: data?.user?.id ?? null };
}

/**
 * Decide where a freshly authenticated user should land based on their
 * admin_users.status. Pure routing logic — accepts an AdminLookup adapter
 * so it can be unit-tested without a live Supabase client.
 *
 * Rules (locked):
 *   - no row              -> /denied?reason=allowlist
 *   - status=deactivated  -> /denied?reason=inactive
 *   - status=invited      -> flip to "verified" then /onboarding
 *   - status=verified     -> /onboarding (user hasn't completed profile)
 *   - status=active       -> `next` (default /dashboard)
 *
 * For invited/verified users, the original `next` is intentionally
 * dropped: they must finish onboarding before any deep link resolves.
 */
export async function resolvePostAuthDestination(args: {
  userId: string | null;
  next: string;
  lookup: AdminLookup;
}): Promise<PostAuthDestination> {
  if (!args.userId) {
    return { kind: "denied", reason: "allowlist" };
  }

  const lookup = await args.lookup.selectStatus(args.userId);
  if (!lookup.ok) {
    return {
      kind: "denied",
      reason: lookup.reason === "not_found" ? "allowlist" : "config",
    };
  }

  switch (lookup.status) {
    case "deactivated":
      return { kind: "denied", reason: "inactive" };
    case "active":
      return { kind: "redirect", path: args.next };
    case "verified":
      return { kind: "redirect", path: "/onboarding" };
    case "invited":
      // Fire-and-forget the flip; even if it fails the user can still
      // complete onboarding (completeOnboardingAction sets status='active'
      // directly), so we don't gate the redirect on it.
      await args.lookup.markVerified(args.userId);
      return { kind: "redirect", path: "/onboarding" };
  }
}
