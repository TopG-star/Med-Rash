type HandlerEvent = {
  httpMethod?: string;
};

type HandlerResponse = {
  statusCode: number;
  headers?: Record<string, string>;
  body: string;
};

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, x-medrash-gate-key",
  "access-control-max-age": "86400",
};

export async function handler(event: HandlerEvent = {}): Promise<HandlerResponse> {
  if ((event.httpMethod ?? "").toUpperCase() === "OPTIONS") {
    return { statusCode: 204, headers: { ...CORS_HEADERS }, body: "" };
  }
  return {
    statusCode: 200,
    headers: {
      "content-type": "application/json",
      ...CORS_HEADERS,
    },
    body: JSON.stringify({
      service: "medrash-admin-functions",
      status: "ok",
    }),
  };
}

export default handler;
