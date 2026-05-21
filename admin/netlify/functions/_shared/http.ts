export type HandlerEvent = {
  httpMethod?: string;
  headers?: Record<string, string | undefined>;
  body?: string | null;
};

export type HandlerResponse = {
  statusCode: number;
  headers?: Record<string, string>;
  body: string;
};

// Browser callers (the Flutter Web participant app on a different Netlify
// site) require CORS headers + an OPTIONS preflight response. Auth is via
// the x-medrash-gate-key header, never cookies, so wildcard origin is safe.
const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, x-medrash-gate-key",
  "access-control-max-age": "86400",
};

export function jsonResponse(statusCode: number, payload: unknown): HandlerResponse {
  return {
    statusCode,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      ...CORS_HEADERS,
    },
    body: JSON.stringify(payload),
  };
}

export function handlePreflight(event: HandlerEvent): HandlerResponse | null {
  if ((event.httpMethod ?? "").toUpperCase() !== "OPTIONS") {
    return null;
  }
  return {
    statusCode: 204,
    headers: { ...CORS_HEADERS },
    body: "",
  };
}

export function parseJsonBody(event: HandlerEvent): Record<string, unknown> {
  const rawBody = event.body;
  if (!rawBody || rawBody.trim().length === 0) {
    return {};
  }

  const parsed = JSON.parse(rawBody) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Request body must be a JSON object.");
  }

  return parsed as Record<string, unknown>;
}

export function requirePost(event: HandlerEvent): HandlerResponse | null {
  if ((event.httpMethod ?? "").toUpperCase() !== "POST") {
    return jsonResponse(405, {
      ok: false,
      message: "Method not allowed. Use POST.",
    });
  }

  return null;
}

// Netlify Functions v2 runtime expects handlers to return a web standard
// Response. Our handlers are written in the classic AWS-Lambda-style shape
// (HandlerEvent in, HandlerResponse out) because that maps cleanly to the
// helpers above. This adapter bridges the two: each function file exports
// `toV2Handler(handler)` as its default export, so the runtime receives a
// real Request/Response pair while the handler logic stays untouched.
export type LegacyHandler = (event: HandlerEvent) => Promise<HandlerResponse>;

export function toV2Handler(legacy: LegacyHandler): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const method = req.method.toUpperCase();
    const headers: Record<string, string> = {};
    req.headers.forEach((value, key) => {
      headers[key.toLowerCase()] = value;
    });

    const hasBody = method !== "GET" && method !== "HEAD" && method !== "OPTIONS";
    const body = hasBody ? await req.text() : null;

    const event: HandlerEvent = { httpMethod: method, headers, body };
    const result = await legacy(event);

    return new Response(result.body, {
      status: result.statusCode,
      headers: result.headers ?? {},
    });
  };
}
