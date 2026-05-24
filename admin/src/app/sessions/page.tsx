import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { PanelCard } from "@/components/panel-card";
import { ScopeToggle, type ScopeValue } from "@/components/scope-toggle";
import { requireAdminSession } from "@/lib/admin-session";
import { buildSessionJoinUrl } from "@/lib/session-create";
import {
  listActiveQuizOptions,
  listAdminSessions,
  type AdminQuizOption,
  type AdminSessionRow,
} from "@/lib/session-queries";

import { SessionCreateForm } from "./session-create-form";
import { SessionRowActions } from "./session-row-actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function formatDate(value: string | null): string {
  if (!value) return "—";
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) return value;
  return new Date(ms).toLocaleString();
}

type SearchParams = { scope?: string };

function parseScope(raw: string | undefined): ScopeValue {
  return raw === "all" ? "all" : "mine";
}

export default async function SessionsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const session = await requireAdminSession({ currentPath: "/sessions" });
  const sp = await searchParams;
  // Hosts can only see their own sessions; owners can toggle scope.
  const scope: ScopeValue =
    session.role === "owner" ? parseScope(sp.scope) : "mine";

  let quizOptions: AdminQuizOption[] = [];
  let sessions: AdminSessionRow[] = [];
  let loadError: string | null = null;

  try {
    [quizOptions, sessions] = await Promise.all([
      listActiveQuizOptions(),
      listAdminSessions({ scope, userId: session.userId }),
    ]);
  } catch (err) {
    loadError = err instanceof Error ? err.message : "Failed to load sessions.";
  }

  return (
    <AdminShell
      title="Sessions"
      subtitle="Create live sessions, attach an approved quiz, and generate QR-linked access for presentation or CME use."
      user={{ email: session.email, role: session.role }}
      actions={
        session.role === "owner" ? (
          <ScopeToggle current={scope} label="Show" />
        ) : null
      }
    >
      {loadError ? (
        <PanelCard className="space-y-2">
          <h2 className="font-[family-name:var(--font-anybody)] text-xl font-extrabold uppercase tracking-tight">
            Unable to load sessions
          </h2>
          <p className="text-sm font-medium text-[var(--arena-ink-muted)]">
            {loadError}
          </p>
          <p className="text-xs font-semibold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            Check that SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and MEDRASH_APP_PUBLIC_BASE_URL are configured.
          </p>
        </PanelCard>
      ) : (
        <PanelCard title="Create New Session">
          <SessionCreateForm quizOptions={quizOptions} />
        </PanelCard>
      )}

      <PanelCard title="Recent Sessions">
        {sessions.length === 0 ? (
          <EmptyState
            icon={<span>📅</span>}
            title="No sessions yet"
            helper="Create one above to generate a QR-coded join link your participants can scan."
          />
        ) : (
          <div className="space-y-4">
            {sessions.map((session) => {
              let joinUrl: string | null = null;
              try {
                joinUrl = buildSessionJoinUrl(session.joinCode);
              } catch {
                joinUrl = null;
              }
              return (
              <div
                key={session.id}
                className="arena-panel flex flex-col gap-4 bg-[var(--arena-surface)] p-4 md:flex-row md:items-center md:justify-between"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <span
                      className={`h-3 w-3 rounded-full ${session.isActiveNow ? "bg-green-500" : "bg-red-400"}`}
                      aria-hidden
                    />
                    <p className="font-semibold">{session.name}</p>
                  </div>
                  <p className="mt-2 text-xs font-bold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
                    Join code · {session.joinCode} · {session.quizTitle}
                  </p>
                  <p className="mt-1 text-sm text-[var(--arena-ink-muted)]">
                    {formatDate(session.startsAt)} → {formatDate(session.endsAt)} ·{" "}
                    {session.attemptCount} attempt{session.attemptCount === 1 ? "" : "s"}
                    {session.hostName ? ` · host ${session.hostName}` : ""}
                  </p>
                </div>
                <div className="flex flex-wrap gap-3">
                  <Link
                    href={`/sessions/${session.id}/live`}
                    className="arena-button bg-[var(--arena-tertiary)] px-4 py-2 text-sm font-semibold"
                  >
                    Live view
                  </Link>
                  {joinUrl ? (
                    <SessionRowActions
                      sessionName={session.name}
                      joinCode={session.joinCode}
                      joinUrl={joinUrl}
                    />
                  ) : (
                    <span className="text-xs font-semibold text-[var(--arena-ink-muted)]">
                      Set MEDRASH_APP_PUBLIC_BASE_URL to enable Copy link / Show QR.
                    </span>
                  )}
                  <button
                    type="button"
                    className="arena-button bg-[var(--arena-primary)] px-4 py-2 text-sm font-semibold opacity-60"
                    disabled
                    title="Export ships with Reports wiring."
                  >
                    Export Data
                  </button>
                </div>
              </div>
              );
            })}
          </div>
        )}
      </PanelCard>
    </AdminShell>
  );
}