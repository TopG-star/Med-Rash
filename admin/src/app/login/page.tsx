import { Suspense } from "react";

import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";

type SearchParams = {
  next?: string;
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

        <p className="vp-fineprint">
          Need access? Ask your MedRash admin to add you as a Host.
        </p>
      </div>
    </main>
  );
}
