// MedRash — Navii avatar endpoint.
//
// Public, unauthenticated. Returns a deterministic SVG mascot per seed via
// `@usenavii/core` (seed in → byte-identical SVG out). Long-immutable
// caching is safe because the package version is pinned in package.json,
// and Navii's determinism contract is "append-only" (new variants never
// shift existing seed selections).
//
// URL shape (preferred — pretty path via redirect in root netlify.toml):
//   GET /avatar/<seed>.svg?size=96&background=ring
// Underlying function path:
//   GET /.netlify/functions/avatar?seed=<seed>&size=96&background=ring
//
// Query params:
//   seed       string  required. Stable per-user id (Supabase UUID
//                      preferred). Trimmed; lowercased only when it matches
//                      a UUID pattern.
//   size       int     16..1024, default 96.
//   background enum    'none' | 'solid' | 'ring'. Optional (seed-derived).
//
// Response: image/svg+xml, immutable for 1y. CORS allow-all (asset).
import { createAvatar } from "@usenavii/core";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VALID_BG = new Set(["none", "solid", "ring"] as const);
type BgKind = "none" | "solid" | "ring";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400",
};

function clampSize(raw: string | null): number {
  const n = raw == null ? NaN : Number.parseInt(raw, 10);
  if (!Number.isFinite(n)) return 96;
  if (n < 16) return 16;
  if (n > 1024) return 1024;
  return n;
}

function normalizeSeed(raw: string): string {
  const trimmed = raw.trim();
  return UUID_RE.test(trimmed) ? trimmed.toLowerCase() : trimmed;
}

export default async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "GET") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { ...CORS_HEADERS, allow: "GET, OPTIONS" },
    });
  }

  const url = new URL(req.url);
  const rawSeed = url.searchParams.get("seed");
  if (!rawSeed || rawSeed.trim().length === 0) {
    return new Response(
      JSON.stringify({ error: "missing required query param: seed" }),
      {
        status: 400,
        headers: { "content-type": "application/json", ...CORS_HEADERS },
      },
    );
  }

  const seed = normalizeSeed(rawSeed);
  const size = clampSize(url.searchParams.get("size"));
  const bgRaw = url.searchParams.get("background");
  const background: BgKind | undefined =
    bgRaw && VALID_BG.has(bgRaw as BgKind) ? (bgRaw as BgKind) : undefined;

  const svg = createAvatar(seed, {
    size,
    ...(background ? { background } : {}),
  });

  return new Response(svg, {
    status: 200,
    headers: {
      "content-type": "image/svg+xml; charset=utf-8",
      "cache-control": "public, max-age=31536000, immutable",
      ...CORS_HEADERS,
    },
  });
};
