import { NextResponse, type NextRequest } from "next/server";

/**
 * Admin portal auth gate.
 *
 * Pilot-grade Basic Auth in front of the entire admin app. The credential is
 * read from `MEDRASH_ADMIN_PORTAL_KEY` (single shared secret). If the env var
 * is unset the middleware is a no-op so local development still works without
 * any setup.
 *
 * Expected `Authorization` header: `Basic base64("admin:<MEDRASH_ADMIN_PORTAL_KEY>")`.
 */
export function middleware(request: NextRequest) {
  const expected = process.env.MEDRASH_ADMIN_PORTAL_KEY;
  if (!expected) {
    return NextResponse.next();
  }

  const header = request.headers.get("authorization") ?? "";
  if (header.toLowerCase().startsWith("basic ")) {
    const encoded = header.slice(6).trim();
    let decoded = "";
    try {
      decoded = atob(encoded);
    } catch {
      decoded = "";
    }
    const idx = decoded.indexOf(":");
    if (idx !== -1) {
      const password = decoded.slice(idx + 1);
      if (password === expected) {
        return NextResponse.next();
      }
    }
  }

  return new NextResponse("Authentication required", {
    status: 401,
    headers: {
      "WWW-Authenticate": 'Basic realm="MedRash Admin", charset="UTF-8"',
    },
  });
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
