import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
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
      <div className="vp-scope vp-vstack vp-vstack-lg">
        {loadError ? (
          <div className="vp-card">
            <h2 className="vp-quiz-title">Unable to load sessions</h2>
            <p className="vp-quiz-summary">{loadError}</p>
            <p className="vp-meta-row vp-mt-3">
              <span>
                Check that SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and
                MEDRASH_APP_PUBLIC_BASE_URL are configured.
              </span>
            </p>
          </div>
        ) : (
          <section className="vp-panel">
            <div className="vp-panel-head">
              <h2 className="vp-panel-title">Create New Session</h2>
            </div>
            <SessionCreateForm quizOptions={quizOptions} />
          </section>
        )}

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Recent Sessions</h2>
          </div>
          {sessions.length === 0 ? (
            <div className="vp-empty">
              <div className="vp-empty-icon">📅</div>
              <h3 className="vp-empty-title">No sessions yet</h3>
              <p className="vp-empty-helper">
                Create one above to generate a QR-coded join link your
                participants can scan.
              </p>
            </div>
          ) : (
            <div className="vp-vstack">
              {sessions.map((row) => {
                let joinUrl: string | null = null;
                try {
                  joinUrl = buildSessionJoinUrl(row.joinCode);
                } catch {
                  joinUrl = null;
                }
                return (
                  <div key={row.id} className="vp-row-card">
                    <div className="vp-min-w-0">
                      <p className="vp-row-title">
                        <span
                          className={`vp-status-dot ${row.isActiveNow ? "is-live" : "is-idle"}`}
                          aria-hidden
                        />
                        {row.name}
                      </p>
                      <p className="vp-meta-row vp-row-meta">
                        <span>Join code · {row.joinCode}</span>
                        <span>{row.quizTitle}</span>
                      </p>
                      <p className="vp-row-sub">
                        {formatDate(row.startsAt)} → {formatDate(row.endsAt)} ·{" "}
                        {row.attemptCount} attempt
                        {row.attemptCount === 1 ? "" : "s"}
                        {row.hostName ? ` · host ${row.hostName}` : ""}
                      </p>
                    </div>
                    <div className="vp-row-card-actions">
                      <Link
                        href={`/sessions/${row.id}/live`}
                        className="vp-button vp-button-secondary vp-button-sm"
                      >
                        Live view
                      </Link>
                      {joinUrl ? (
                        <SessionRowActions
                          sessionName={row.name}
                          joinCode={row.joinCode}
                          joinUrl={joinUrl}
                        />
                      ) : (
                        <span className="vp-help-text">
                          Set MEDRASH_APP_PUBLIC_BASE_URL to enable Copy link /
                          Show QR.
                        </span>
                      )}
                      <button
                        type="button"
                        className="vp-button vp-button-primary vp-button-sm vp-disabled-soft"
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
        </section>
      </div>
    </AdminShell>
  );
}