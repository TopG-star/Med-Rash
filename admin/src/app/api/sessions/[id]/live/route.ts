import { NextResponse } from "next/server";

import { getSessionLiveSnapshot } from "@/lib/session-queries";

export const dynamic = "force-dynamic";

type RouteParams = {
  params: Promise<{ id: string }>;
};

export async function GET(_request: Request, { params }: RouteParams) {
  const { id } = await params;
  try {
    const snapshot = await getSessionLiveSnapshot(id);
    if (!snapshot) {
      return NextResponse.json(
        { ok: false, message: "Session not found." },
        { status: 404 },
      );
    }
    return NextResponse.json(snapshot, {
      headers: { "cache-control": "no-store" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to load live snapshot.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
