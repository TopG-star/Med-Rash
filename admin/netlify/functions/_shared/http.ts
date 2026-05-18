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

export function jsonResponse(statusCode: number, payload: unknown): HandlerResponse {
  return {
    statusCode,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
    body: JSON.stringify(payload),
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
