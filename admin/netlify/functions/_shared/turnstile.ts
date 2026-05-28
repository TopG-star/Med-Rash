// Slice A2 phase 3b — Cloudflare Turnstile verifier for the
// `/device-token` mint endpoint.
//
// Replaces the static `x-medrash-gate-key` bootstrap with a fresh,
// short-lived (single-use, ~5min) challenge response that proves a real
// browser solved the (invisible) widget. Cloudflare's siteverify endpoint
// returns `{success: bool, error-codes: string[]}` on validation; we
// surface a simplified `{ok, errorCodes}` shape to keep call sites
// branch-free.
//
// Env:
//   MEDRASH_TURNSTILE_SECRET — server secret from the Cloudflare dashboard
//                              (NOT the site key). Required.
//
// Bypass:
//   MEDRASH_TURNSTILE_BYPASS_TOKEN — optional. When set AND the request
//   sends exactly this token, verification short-circuits to ok=true. Used
//   only for hosted smoke-tests + CI scripts. Leave unset in production.

export type TurnstileVerifyResult = {
  ok: boolean;
  errorCodes: string[];
  errorMessage?: string;
};

const SITEVERIFY_URL =
  "https://challenges.cloudflare.com/turnstile/v0/siteverify";

export async function verifyTurnstileToken(
  token: string,
  remoteIp?: string | null,
): Promise<TurnstileVerifyResult> {
  const trimmed = token.trim();
  if (trimmed.length === 0) {
    return {
      ok: false,
      errorCodes: ["missing-input-response"],
      errorMessage: "Missing turnstile token.",
    };
  }

  const bypass = process.env.MEDRASH_TURNSTILE_BYPASS_TOKEN?.trim() ?? "";
  if (bypass.length > 0 && trimmed === bypass) {
    return { ok: true, errorCodes: [] };
  }

  const secret = process.env.MEDRASH_TURNSTILE_SECRET?.trim() ?? "";
  if (secret.length === 0) {
    return {
      ok: false,
      errorCodes: ["missing-input-secret"],
      errorMessage: "MEDRASH_TURNSTILE_SECRET env var is not configured.",
    };
  }

  const form = new URLSearchParams();
  form.set("secret", secret);
  form.set("response", trimmed);
  if (remoteIp && remoteIp.length > 0) {
    form.set("remoteip", remoteIp);
  }

  let resp: Response;
  try {
    resp = await fetch(SITEVERIFY_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
  } catch (error) {
    return {
      ok: false,
      errorCodes: ["network-error"],
      errorMessage:
        error instanceof Error
          ? error.message
          : "Network error contacting Cloudflare siteverify.",
    };
  }

  if (!resp.ok) {
    return {
      ok: false,
      errorCodes: [`siteverify-http-${resp.status}`],
      errorMessage: `siteverify returned HTTP ${resp.status}.`,
    };
  }

  let parsed: unknown;
  try {
    parsed = await resp.json();
  } catch {
    return {
      ok: false,
      errorCodes: ["siteverify-bad-json"],
      errorMessage: "siteverify response was not valid JSON.",
    };
  }

  if (!parsed || typeof parsed !== "object") {
    return {
      ok: false,
      errorCodes: ["siteverify-bad-shape"],
      errorMessage: "siteverify response was not an object.",
    };
  }

  const obj = parsed as Record<string, unknown>;
  const success = obj.success === true;
  const errorCodesRaw = obj["error-codes"];
  const errorCodes: string[] = Array.isArray(errorCodesRaw)
    ? errorCodesRaw.filter((x): x is string => typeof x === "string")
    : [];

  if (success) {
    return { ok: true, errorCodes: [] };
  }

  return {
    ok: false,
    errorCodes: errorCodes.length > 0 ? errorCodes : ["unknown"],
    errorMessage: "Cloudflare rejected the turnstile token.",
  };
}

/** Best-effort caller IP extraction from Netlify/Cloudflare proxy headers. */
export function extractRemoteIp(
  headers: Record<string, string | undefined> | undefined,
): string | null {
  if (!headers) return null;
  const xff =
    headers["x-nf-client-connection-ip"] ??
    headers["cf-connecting-ip"] ??
    headers["x-forwarded-for"];
  if (!xff) return null;
  const first = xff.split(",")[0]?.trim();
  return first && first.length > 0 ? first : null;
}
