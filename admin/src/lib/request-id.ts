/**
 * P1.3 — X-Request-ID correlation.
 *
 * One header travels through the entire stack so a single user action can
 * be traced across middleware -> route handlers -> Netlify functions ->
 * Sentry events:
 *
 *   1. Flutter client mints one ID per outbound HTTP call.
 *   2. Admin middleware mints one if the incoming request has none, then
 *      propagates it to downstream handlers via the request headers and
 *      echoes it on the response.
 *   3. Sentry's beforeSend hook in admin/src/lib/observability/sentry-scrubber.ts
 *      promotes `event.request.headers['x-request-id']` to the
 *      `request_id` event tag so every captured exception is filterable.
 *
 * The header name is lowercase by convention; HTTP headers are
 * case-insensitive but most logs preserve the supplied casing — keeping
 * it lowercase end-to-end means grep'ing is trivial.
 *
 * Format: 16 hex chars from crypto.randomUUID() (truncated). Short enough
 * to scan in logs, wide enough to be globally unique within a session.
 */

export const REQUEST_ID_HEADER = "x-request-id";

const ID_BYTES = 8; // 16 hex chars after stringification

/**
 * Mint a fresh request id. Backed by crypto.getRandomValues so it works
 * on every runtime (Edge, Node, browser, V8 isolates) without taking a
 * dependency on Node's `crypto` module.
 */
export function mintRequestId(): string {
  const bytes = new Uint8Array(ID_BYTES);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const b of bytes) {
    out += b.toString(16).padStart(2, "0");
  }
  return out;
}

/**
 * Validate that an incoming X-Request-ID we trust enough to echo. Loose
 * on purpose: accept anything ASCII-printable up to 128 chars, lower-case
 * for storage. Rejecting overlong / control-character values prevents log
 * injection if a hostile client pads the header.
 */
const ID_OK = /^[\x21-\x7e]{1,128}$/;

export function readRequestId(headers: Headers | Record<string, string | undefined>): string | null {
  const raw =
    headers instanceof Headers
      ? headers.get(REQUEST_ID_HEADER)
      : headers[REQUEST_ID_HEADER] ?? headers[REQUEST_ID_HEADER.toUpperCase()] ?? null;
  if (!raw) return null;
  const trimmed = raw.trim();
  if (!ID_OK.test(trimmed)) return null;
  return trimmed.toLowerCase();
}

/**
 * Read the incoming X-Request-ID, or mint a new one if absent/invalid.
 */
export function getOrMintRequestId(
  headers: Headers | Record<string, string | undefined>,
): string {
  return readRequestId(headers) ?? mintRequestId();
}
