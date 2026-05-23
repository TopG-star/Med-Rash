import Link from "next/link";

export const dynamic = "force-dynamic";

type SearchParams = { reason?: string };

const REASON_COPY: Record<string, string> = {
  config: "The server is missing Supabase credentials. Ask the platform owner to set SUPABASE_URL and SUPABASE_ANON_KEY.",
  exchange: "We could not complete sign-in. Request a new magic link.",
  role: "That page requires Owner access. Ask an Owner to promote your role.",
};

export default async function DeniedPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const reason = typeof params.reason === "string" ? params.reason : "";
  const detail = REASON_COPY[reason] ?? "Your account is not on the MedRash admin allowlist. Ask an Owner to invite you.";

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-5 px-6 py-12">
      <p className="text-xs font-extrabold uppercase tracking-[0.15em] text-[var(--arena-ink-muted)]">
        MedRash Admin
      </p>
      <h1 className="font-[family-name:var(--font-anybody)] text-4xl font-extrabold tracking-tight">
        Access denied
      </h1>
      <p className="text-sm text-[var(--arena-ink-muted)]">{detail}</p>
      <div className="flex flex-wrap gap-3">
        <Link
          href="/login"
          className="arena-button bg-[var(--arena-primary)] px-5 py-3 font-semibold"
        >
          Back to sign-in
        </Link>
        <a
          href="/auth/signout"
          className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold"
        >
          Sign out
        </a>
      </div>
    </main>
  );
}
