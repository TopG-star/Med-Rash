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
 * Handle the GET side of /auth/callback. Always signs out the existing
 * cookie session FIRST so that, if the visitor is opening an invite (or any
 * magic link) in a browser already authenticated as someone else, the prior
 * session is gone before the new tokens land. Order is critical: signOut
 * after exchangeCodeForSession would wipe the freshly-set cookies.
 */
export async function handleAuthCallbackGet(args: {
  supabase: CallbackSupabase;
  code: string | null;
}): Promise<CallbackOutcome> {
  const { supabase, code } = args;

  // 1) Wipe any session cookie the browser arrived with. This is the line
  //    that prevents the "owner already logged in -> invitee sees owner"
  //    confidentiality break.
  await supabase.auth.signOut();

  // 2a) PKCE path: server-visible ?code= parameter.
  if (code) {
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      return { ok: false, reason: "exchange", message: error.message };
    }
    return { ok: true, userId: data?.user?.id ?? null };
  }

  // 2b) Hash-fragment path: tokens are in window.location.hash and never
  //     reach the server. The route renders an interstitial that POSTs them
  //     back. We do NOT silently redirect to the dashboard here — that was
  //     the original bug.
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
