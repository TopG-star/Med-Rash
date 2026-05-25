import {
  findUserByRecoveryEmail,
  getSupabaseAdminClient,
  getSupabaseAuthClient,
} from "./_shared/supabase";
import {
  HandlerEvent,
  HandlerResponse,
  handlePreflight,
  jsonResponse,
  parseJsonBody,
  requirePost,
  toV2Handler,
} from "./_shared/http";
import { requireGateAuthorization } from "./_shared/gate";

// Slice 6b — step 1 of OTP-confirmed identity recovery.
//
// Flow:
//   1. Client posts { email } from the /recover entry page.
//   2. Look up app.users by lower(email). If no row carries that email,
//      return 404 PROFILE_NOT_FOUND so the UI can say "no profile found".
//   3. Ask Supabase Auth to send a one-time code to that email via the
//      anon-keyed auth client (signInWithOtp). shouldCreateUser is true so
//      the auth.users row is provisioned lazily on first recover; that row
//      is what we'll write into app.users.claimed_auth_user_id on step 2.
//
// Rate limiting is delegated to Supabase Auth (per-email + per-project).
// Verification lives in recover-verify.ts.
export async function handler(event: HandlerEvent): Promise<HandlerResponse> {
  const preflight = handlePreflight(event);
  if (preflight) {
    return preflight;
  }

  const methodResponse = requirePost(event);
  if (methodResponse) {
    return methodResponse;
  }

  const gateResponse = requireGateAuthorization(event);
  if (gateResponse) {
    return gateResponse;
  }

  try {
    const body = parseJsonBody(event);
    const rawEmail = typeof body.email === "string" ? body.email : "";
    const email = rawEmail.trim().toLowerCase();

    if (!email) {
      return jsonResponse(400, {
        ok: false,
        code: "BAD_REQUEST",
        message: "Enter the email you used when you created your profile.",
      });
    }

    const supabase = getSupabaseAdminClient();
    const existing = await findUserByRecoveryEmail(supabase, email);

    if (!existing) {
      return jsonResponse(404, {
        ok: false,
        code: "PROFILE_NOT_FOUND",
        message: "No profile is linked to that email. Check the spelling or start a new profile.",
      });
    }

    const auth = getSupabaseAuthClient();
    const { error } = await auth.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: true,
      },
    });

    if (error) {
      const status = typeof (error as { status?: number }).status === "number" ? (error as { status: number }).status : 0;
      if (status === 429) {
        return jsonResponse(429, {
          ok: false,
          code: "RATE_LIMITED",
          message: "Too many recovery codes requested. Wait a minute and try again.",
        });
      }
      return jsonResponse(502, {
        ok: false,
        code: "OTP_SEND_FAILED",
        message: "Couldn't send the recovery code. Try again in a moment.",
      });
    }

    return jsonResponse(200, {
      ok: true,
      message: "Recovery code sent. Check your email.",
    });
  } catch (error) {
    return jsonResponse(400, {
      ok: false,
      code: "BAD_REQUEST",
      message: error instanceof Error ? error.message : "Invalid request.",
    });
  }
}

export default toV2Handler(handler);
