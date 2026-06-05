// Login is a two-step OTP flow:
//   1. user submits email          -> "code_sent"
//   2. user submits 6-digit token  -> "verified" (client navigates) or "error"
// Magic link still works as a fallback (Supabase sends both the OTP and a
// link in the same email; the link routes through /auth/callback).
//
// On success the verify action returns "verified" rather than calling the
// server-side redirect(). A Server-Action redirect whose target is itself
// re-redirected by middleware / chained page guards (/, /dashboard, then the
// owner AAL2 gate -> /onboarding/mfa) makes the Next.js flight parser throw
// "An unexpected response was received from the server." We instead hand the
// destination back to the client, which does a normal full-page navigation
// that follows the 307 chain natively with the freshly-set auth cookies.

export type LoginActionState =
  | { status: "idle"; message: "" }
  | {
      status: "code_sent";
      message: string;
      email: string;
      next: string;
      /** Epoch ms after which a fresh OTP may be requested. */
      nextResendAt: number;
    }
  | {
      // Verify succeeded; the client performs the post-auth navigation.
      status: "verified";
      next: string;
    }
  | {
      status: "error";
      message: string;
      // When the error happens during verify, we want to stay on step 2 with
      // the same email pre-filled, so we round-trip it through state.
      email?: string;
      next?: string;
      nextResendAt?: number;
    };

export const initialLoginState: LoginActionState = {
  status: "idle",
  message: "",
};
