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
