// Pure v2 native handler — accepts a Request, returns a Response. Lives
// outside the legacy shape so it has zero deps on the shared helpers.
const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, x-medrash-gate-key",
  "access-control-max-age": "86400",
};

export default async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  return new Response(
    JSON.stringify({ service: "medrash-admin-functions", status: "ok" }),
    {
      status: 200,
      headers: { "content-type": "application/json", ...CORS_HEADERS },
    },
  );
};
