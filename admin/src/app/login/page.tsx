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
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-6 px-6 py-12">
      <header className="space-y-2">
        <p className="text-xs font-extrabold uppercase tracking-[0.15em] text-[var(--arena-ink-muted)]">
          MedRash Admin
        </p>
        <h1 className="font-[family-name:var(--font-anybody)] text-4xl font-extrabold tracking-tight">
          Sign in
        </h1>
        <p className="text-sm text-[var(--arena-ink-muted)]">
          We&apos;ll email you a one-time magic link. Only allowlisted
          addresses can reach the dashboard.
        </p>
      </header>
      <Suspense fallback={null}>
        <LoginForm next={next} />
      </Suspense>
    </main>
  );
}
