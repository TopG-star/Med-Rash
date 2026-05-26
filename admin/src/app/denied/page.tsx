import Link from "next/link";

export const dynamic = "force-dynamic";

type SearchParams = { reason?: string };

const REASON_COPY: Record<string, string> = {
  config: "The server is missing Supabase credentials. Ask the platform owner to set SUPABASE_URL and SUPABASE_ANON_KEY.",
  exchange: "We could not complete sign-in. Request a new magic link.",
  role: "That page is Owner-only. Ask an Owner to promote your role.",
  callback_no_code: "Your sign-in link is missing or expired. Request a new invite or magic link.",
  set_session: "We could not establish your session. Request a new invite or magic link.",
  allowlist: "Your account is not on the MedRash admin allowlist. Ask an Owner to invite you.",
  inactive: "Your access has been deactivated. Ask an Owner to reactivate your account.",
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
                d="M9 9l6 6M15 9l-6 6"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
              />
            </svg>
          </span>
          <p className="vp-eyebrow">MedRash Admin</p>
          <h1 className="vp-display">
            Access <span className="vp-display-accent">denied</span>
          </h1>
          <p className="vp-tagline">{detail}</p>
        </div>

        <div className="vp-card">
          <div className="vp-button-row">
            <Link href="/login" className="vp-button vp-button-primary">
              Back to sign-in
            </Link>
            <a href="/auth/signout" className="vp-button vp-button-secondary">
              Sign out
            </a>
          </div>
        </div>
      </div>
    </main>
  );
}
