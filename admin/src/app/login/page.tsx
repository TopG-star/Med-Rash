import { Suspense } from "react";
import { headers } from "next/headers";

import { logAuthEvent } from "@/lib/audit";
import { getAdminSupabaseClient } from "@/lib/supabase-server";

import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";

type SearchParams = {
  next?: string;
  reason?: string;
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const next = typeof params.next === "string" && params.next.startsWith("/")
    ? params.next
    : "/dashboard";

  // Slice B1 P3 — when the middleware bounces a stale admin session back
  // to /login with ?reason=session_idle|session_absolute, capture an
  // audit event (fire-and-forget; the page render is the user-visible
  // signal). We are deliberately in the Node runtime here, so
  // `logAuthEvent` + `getAdminSupabaseClient` are safe to use.
  const reason = typeof params.reason === "string" ? params.reason : null;
  if (reason === "session_idle" || reason === "session_absolute") {
    try {
      const h = await headers();
      const xff = h.get("x-forwarded-for");
      const ip = xff ? (xff.split(",")[0]?.trim() ?? null) : null;
      const userAgent = h.get("user-agent");
      void logAuthEvent(getAdminSupabaseClient(), {
        eventType:
          reason === "session_idle"
            ? "session_idle_timeout"
            : "session_absolute_timeout",
        ip,
        userAgent,
        result: "ok",
        metadata: { next },
      });
    } catch (err) {
      // Audit logging must never break the login page render.
      console.error("[login] session-timeout audit emit failed", err);
    }
  }

  return (
    <main className="vp-auth">
      <div className="vp-stack">
        <div className="vp-hero">
          <span aria-hidden className="vp-logo-tile">
            <svg
              width="32"
              height="32"
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M12 2 4 5v6c0 5 3.5 9.4 8 11 4.5-1.6 8-6 8-11V5l-8-3Z"
                fill="currentColor"
                fillOpacity="0.18"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinejoin="round"
              />
              <path
                d="M12 8v6M9 11h6"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
              />
            </svg>
          </span>
          <p className="vp-eyebrow">MedRash Admin</p>
          <h1 className="vp-display">
            Sign <span className="vp-display-accent">in</span>
          </h1>
          <p className="vp-tagline">
            We&apos;ll email you a 6-digit code. Only allowlisted addresses can
            reach the dashboard.
          </p>
        </div>

        <Suspense fallback={null}>
          <LoginForm next={next} />
        </Suspense>

        {reason === "session_idle" ? (
          <p className="vp-banner vp-banner-info" role="status">
            Your session timed out after 30 minutes of inactivity. Sign in again
            to continue.
          </p>
        ) : null}
        {reason === "session_absolute" ? (
          <p className="vp-banner vp-banner-info" role="status">
            Your session reached its 8-hour maximum. Sign in again to continue.
          </p>
        ) : null}

        <p className="vp-fineprint">
          Need access? Ask your MedRash admin to add you as a Host.
        </p>
      </div>
    </main>
  );
}
