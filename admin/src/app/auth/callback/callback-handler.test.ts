import { describe, expect, it, vi } from "vitest";

import {
  handleAuthCallbackGet,
  handleAuthCallbackPost,
  resolvePostAuthDestination,
  type AdminLookup,
  type AdminStatus,
  type CallbackSupabase,
} from "./callback-handler";

/**
 * Build a fake Supabase auth client whose call order we can inspect.
 * `currentUserId` simulates the user currently held in the cookie session.
 */
function makeFakeSupabase(opts: {
  currentUserId: string | null;
  exchangeResult?: { userId: string | null; error?: string };
  setSessionResult?: { userId: string | null; error?: string };
}): { supabase: CallbackSupabase; calls: string[]; sessionUserId: () => string | null } {
  const calls: string[] = [];
  let sessionUserId: string | null = opts.currentUserId;

  const supabase: CallbackSupabase = {
    auth: {
      signOut: vi.fn(async () => {
        calls.push("signOut");
        sessionUserId = null;
        return { error: null };
      }),
      exchangeCodeForSession: vi.fn(async (_code: string) => {
        calls.push("exchangeCodeForSession");
        if (opts.exchangeResult?.error) {
          return {
            data: null,
            error: { message: opts.exchangeResult.error },
          };
        }
        sessionUserId = opts.exchangeResult?.userId ?? null;
        return {
          data: { user: sessionUserId ? { id: sessionUserId } : null },
          error: null,
        };
      }),
      setSession: vi.fn(async (_input) => {
        calls.push("setSession");
        if (opts.setSessionResult?.error) {
          return {
            data: null,
            error: { message: opts.setSessionResult.error },
          };
        }
        sessionUserId = opts.setSessionResult?.userId ?? null;
        return {
          data: { user: sessionUserId ? { id: sessionUserId } : null },
          error: null,
        };
      }),
    },
  };

  return { supabase, calls, sessionUserId: () => sessionUserId };
}

describe("handleAuthCallbackGet — PKCE path (with ?code=)", () => {
  it("does NOT signOut before exchange (would wipe the PKCE code_verifier)", async () => {
    // Owner is already signed in (cookie present). The PKCE exchange must
    // still succeed because exchangeCodeForSession needs the code_verifier
    // cookie that signInWithOtp set on this browser.
    const fake = makeFakeSupabase({
      currentUserId: "owner-uuid",
      exchangeResult: { userId: "invitee-uuid" },
    });

    const result = await handleAuthCallbackGet({
      supabase: fake.supabase,
      code: "invitee-code",
    });

    // No signOut on the PKCE path — that would break self-initiated magic
    // link login by wiping the code_verifier cookie.
    expect(fake.calls).toEqual(["exchangeCodeForSession"]);
    expect(result).toEqual({ ok: true, userId: "invitee-uuid" });
  });

  it("invitee session displaces the owner cookie via exchange overwrite", async () => {
    // exchangeCodeForSession atomically overwrites the sb-* session cookies
    // with the new user's tokens, so the prior admin's session does not
    // survive even though we did not call signOut.
    const fake = makeFakeSupabase({
      currentUserId: "owner-uuid",
      exchangeResult: { userId: "invitee-uuid" },
    });

    await handleAuthCallbackGet({
      supabase: fake.supabase,
      code: "invitee-code",
    });

    expect(fake.sessionUserId()).toBe("invitee-uuid");
    expect(fake.sessionUserId()).not.toBe("owner-uuid");
  });

  it("returns ok:false with reason=exchange when exchange fails", async () => {
    const fake = makeFakeSupabase({
      currentUserId: null,
      exchangeResult: { userId: null, error: "invalid grant" },
    });

    const result = await handleAuthCallbackGet({
      supabase: fake.supabase,
      code: "bad-code",
    });

    expect(result).toEqual({
      ok: false,
      reason: "exchange",
      message: "invalid grant",
    });
  });
});

describe("handleAuthCallbackGet — hash flow (no ?code=)", () => {
  it("signs out the prior session and returns needsHashFlow", async () => {
    const fake = makeFakeSupabase({ currentUserId: "owner-uuid" });

    const result = await handleAuthCallbackGet({
      supabase: fake.supabase,
      code: null,
    });

    // Hash flow has no code_verifier in play, so signOut is safe — and
    // necessary, so the visitor does not see the prior dashboard while the
    // interstitial JS runs.
    expect(fake.calls).toEqual(["signOut"]);
    expect(result).toEqual({ needsHashFlow: true });
    expect(fake.sessionUserId()).toBeNull();
  });
});

describe("handleAuthCallbackPost", () => {
  it("signs out before setSession so the new tokens overwrite a clean slate", async () => {
    const fake = makeFakeSupabase({
      currentUserId: "owner-uuid",
      setSessionResult: { userId: "invitee-uuid" },
    });

    const result = await handleAuthCallbackPost({
      supabase: fake.supabase,
      accessToken: "at",
      refreshToken: "rt",
    });

    expect(fake.calls).toEqual(["signOut", "setSession"]);
    expect(result).toEqual({ ok: true, userId: "invitee-uuid" });
    expect(fake.sessionUserId()).toBe("invitee-uuid");
  });

  it("rejects missing tokens", async () => {
    const fake = makeFakeSupabase({ currentUserId: null });

    const result = await handleAuthCallbackPost({
      supabase: fake.supabase,
      accessToken: null,
      refreshToken: null,
    });

    expect(result).toEqual({ ok: false, reason: "no_code_no_hash" });
    // Must not have touched auth at all when input was invalid.
    expect(fake.calls).toEqual([]);
  });

  it("returns ok:false with reason=set_session when setSession fails", async () => {
    const fake = makeFakeSupabase({
      currentUserId: null,
      setSessionResult: { userId: null, error: "bad token" },
    });

    const result = await handleAuthCallbackPost({
      supabase: fake.supabase,
      accessToken: "at",
      refreshToken: "rt",
    });

    expect(result).toEqual({
      ok: false,
      reason: "set_session",
      message: "bad token",
    });
  });
});

function makeFakeLookup(
  init:
    | { ok: true; status: AdminStatus }
    | { ok: false; reason: "not_found" | "error" },
): { lookup: AdminLookup; markVerifiedCalls: number; current: () => AdminStatus | null } {
  let current: AdminStatus | null = init.ok ? init.status : null;
  let markVerifiedCalls = 0;
  const lookup: AdminLookup = {
    selectStatus: vi.fn(async (_userId: string) => {
      if (!init.ok) return { ok: false as const, reason: init.reason };
      return { ok: true as const, status: current ?? init.status };
    }),
    markVerified: vi.fn(async (_userId: string) => {
      markVerifiedCalls += 1;
      if (current === "invited") current = "verified";
      return { ok: true as const };
    }),
  };
  return {
    lookup,
    get markVerifiedCalls() {
      return markVerifiedCalls;
    },
    current: () => current,
  } as unknown as { lookup: AdminLookup; markVerifiedCalls: number; current: () => AdminStatus | null };
}

describe("resolvePostAuthDestination", () => {
  it("denies with allowlist when userId is null (no session)", async () => {
    const fake = makeFakeLookup({ ok: true, status: "active" });
    const dest = await resolvePostAuthDestination({
      userId: null,
      next: "/dashboard",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "denied", reason: "allowlist" });
    expect(fake.lookup.selectStatus).not.toHaveBeenCalled();
  });

  it("denies with allowlist when admin_users row is missing", async () => {
    const fake = makeFakeLookup({ ok: false, reason: "not_found" });
    const dest = await resolvePostAuthDestination({
      userId: "u",
      next: "/dashboard",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "denied", reason: "allowlist" });
  });

  it("denies with config on lookup error (so we don't leak access on DB failure)", async () => {
    const fake = makeFakeLookup({ ok: false, reason: "error" });
    const dest = await resolvePostAuthDestination({
      userId: "u",
      next: "/dashboard",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "denied", reason: "config" });
  });

  it("denies with inactive for deactivated users", async () => {
    const fake = makeFakeLookup({ ok: true, status: "deactivated" });
    const dest = await resolvePostAuthDestination({
      userId: "u",
      next: "/dashboard",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "denied", reason: "inactive" });
    expect(fake.lookup.markVerified).not.toHaveBeenCalled();
  });

  it("flips invited -> verified and routes to /onboarding", async () => {
    const fake = makeFakeLookup({ ok: true, status: "invited" });
    const dest = await resolvePostAuthDestination({
      userId: "u",
      next: "/dashboard",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "redirect", path: "/onboarding" });
    expect(fake.lookup.markVerified).toHaveBeenCalledTimes(1);
    expect(fake.current()).toBe("verified");
  });

  it("routes verified users to /onboarding without re-flipping", async () => {
    const fake = makeFakeLookup({ ok: true, status: "verified" });
    const dest = await resolvePostAuthDestination({
      userId: "u",
      next: "/dashboard",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "redirect", path: "/onboarding" });
    expect(fake.lookup.markVerified).not.toHaveBeenCalled();
  });

  it("active users go to next (honoring a deep link)", async () => {
    const fake = makeFakeLookup({ ok: true, status: "active" });
    const dest = await resolvePostAuthDestination({
      userId: "u",
      next: "/quiz-bank",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "redirect", path: "/quiz-bank" });
  });

  it("invited users do NOT keep the deep link — onboarding interrupts", async () => {
    const fake = makeFakeLookup({ ok: true, status: "invited" });
    const dest = await resolvePostAuthDestination({
      userId: "u",
      next: "/quiz-bank",
      lookup: fake.lookup,
    });
    expect(dest).toEqual({ kind: "redirect", path: "/onboarding" });
  });
});
