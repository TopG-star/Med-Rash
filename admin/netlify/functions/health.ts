// Pure v2 native handler — accepts a Request, returns a Response. Lives
// outside the legacy shape so it has zero deps on the shared helpers.
import { getOrMintRequestId } from "../../src/lib/request-id";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, authorization, x-request-id, idempotency-key",
  "access-control-expose-headers": "x-request-id",
  "access-control-max-age": "86400",
};

export default async (req: Request): Promise<Response> => {
  const requestId = getOrMintRequestId(req.headers);
  const baseHeaders = { ...CORS_HEADERS, "x-request-id": requestId };
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: baseHeaders });
  }
  return new Response(
    JSON.stringify({ service: "medrash-admin-functions", status: "ok" }),
    {
      status: 200,
      headers: { "content-type": "application/json", ...baseHeaders },
    },
  );
};
