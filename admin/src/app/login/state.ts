// Login is a two-step OTP flow:
//   1. user submits email          -> "code_sent"
//   2. user submits 6-digit token  -> redirect (server) or "error"
// Magic link still works as a fallback (Supabase sends both the OTP and a
// link in the same email; the link routes through /auth/callback).

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
