import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";
import { getOverviewKpis } from "@/lib/overview-queries";
import { getMostMissed, getFacilityPerformance } from "@/lib/reports-queries";
import { widthClassFromPercent } from "@/lib/width-class";

export const dynamic = "force-dynamic";

function clampPercent(value: number): number {
  if (!Number.isFinite(value)) return 0;
  if (value < 0) return 0;
  if (value > 100) return 100;
  return Math.round(value);
}

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1).trimEnd()}\u2026`;
}

function formatPercent(value: number | null): string {
  if (value === null) return "\u2014";
  return `${Math.round(value)}%`;
}

function facilityToneClass(avg: number | null): string {
  if (avg === null) return "";
  if (avg < 60) return "is-danger";
  if (avg < 80) return "is-warn";
  return "is-success";
}

export default async function DashboardPage() {
  const session = await requireAdminSession({ currentPath: "/dashboard" });
  const createdBy = session.role === "host" ? session.userId : null;
  let loadError: string | null = null;
  let kpis = {
    totalUsers: 0,
    completedAttempts: 0,
    averageScorePercent: null as number | null,
    activeQuizzes: 0,
  };
  let mostMissed: Awaited<ReturnType<typeof getMostMissed>> = [];
  let facilityPerformance: Awaited<ReturnType<typeof getFacilityPerformance>> = [];

  try {
    [kpis, mostMissed, facilityPerformance] = await Promise.all([
      getOverviewKpis({ createdBy }),
      getMostMissed(4, {}, { createdBy }),
      getFacilityPerformance(3, { createdBy }),
    ]);
  } catch (error) {
    loadError = error instanceof Error ? error.message : "Failed to load dashboard data.";
  }

  const completionDelta =
    kpis.completedAttempts > 0
      ? `${kpis.completedAttempts.toLocaleString()} attempts completed`
      : "No completed attempts yet";

  return (
    <AdminShell
      title="Dashboard Overview"
      subtitle="Monitor pilot performance, participation quality, and the most immediate knowledge-gap signals."
      user={{ email: session.email, role: session.role }}
      actions={
        <span className="vp-scope">
          <a className="vp-button vp-button-primary" href="/reports">
            Open Reports
          </a>
        </span>
      }
    >
      <div className="vp-scope vp-dashboard">
        {loadError && (
          <section className="vp-banner-warn" role="alert">
            <strong>Dashboard data unavailable</strong>
            {loadError}
          </section>
        )}

        <section className="vp-hero-card" aria-label="Pilot summary">
          <p className="vp-hero-eyebrow">MedRash Pilot</p>
          <h2 className="vp-hero-title">
            {kpis.totalUsers.toLocaleString()} participants in motion
          </h2>
          <p className="vp-hero-sub">
            Pulse of the active cohort — completion velocity, score signal, and
            the knowledge gaps that need a coach today.
          </p>
          <div className="vp-hero-chips">
            <span className="vp-chip vp-chip-secondary">
              {kpis.activeQuizzes} active {kpis.activeQuizzes === 1 ? "quiz" : "quizzes"}
            </span>
            <span className="vp-chip">
              {kpis.completedAttempts.toLocaleString()} completed attempts
            </span>
            <span className="vp-chip">
              Avg score {formatPercent(kpis.averageScorePercent)}
            </span>
          </div>
        </section>

        <section className="vp-stat-grid" aria-label="Key metrics">
          <article className="vp-stat-tile">
            <span className="vp-stat-icon" aria-hidden>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                <circle cx="9" cy="7" r="4" />
                <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                <path d="M16 3.13a4 4 0 0 1 0 7.75" />
              </svg>
            </span>
            <p className="vp-stat-label">Total Participants</p>
            <p className="vp-stat-value">{kpis.totalUsers.toLocaleString()}</p>
            <p className="vp-stat-delta">
              {kpis.activeQuizzes} active {kpis.activeQuizzes === 1 ? "quiz" : "quizzes"}
            </p>
          </article>
          <article className="vp-stat-tile">
            <span className="vp-stat-icon is-mint" aria-hidden>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="20 6 9 17 4 12" />
              </svg>
            </span>
            <p className="vp-stat-label">Completed Attempts</p>
            <p className="vp-stat-value">{kpis.completedAttempts.toLocaleString()}</p>
            <p className="vp-stat-delta">{completionDelta}</p>
          </article>
          <article className="vp-stat-tile">
            <span className="vp-stat-icon is-gold" aria-hidden>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 2 15.09 8.26 22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
              </svg>
            </span>
            <p className="vp-stat-label">Average Score</p>
            <p className="vp-stat-value">{formatPercent(kpis.averageScorePercent)}</p>
            <p className="vp-stat-delta">Rolling 30-day window</p>
          </article>
        </section>

        <section className="vp-grid-2" aria-label="Quality signals">
          <article className="vp-panel">
            <header className="vp-panel-head">
              <h2 className="vp-panel-title">Most-Missed Questions</h2>
              <span className="vp-panel-meta">Top {mostMissed.length || 4}</span>
            </header>
            {mostMissed.length === 0 ? (
              <div className="vp-empty">
                <span className="vp-empty-icon" aria-hidden>📊</span>
                <h3 className="vp-empty-title">No answer data yet</h3>
                <p className="vp-empty-helper">
                  Once your first participant submits, this panel will populate
                  within seconds.
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {mostMissed.map((row) => {
                  const wrongPercent = clampPercent(row.incorrectRate);
                  return (
                    <div key={row.questionId} className="vp-row">
                      <span className="vp-row-label" title={row.quizTitle}>
                        {truncate(row.quizTitle || "(quiz)", 22)}
                      </span>
                      <div
                        className="vp-bar"
                        title={row.prompt}
                      >
                        <div
                          className={["vp-bar-fill", widthClassFromPercent(wrongPercent)].join(" ")}
                        />
                      </div>
                      <span className="vp-row-value">{wrongPercent}% wrong</span>
                    </div>
                  );
                })}
              </div>
            )}
          </article>

          <article className="vp-panel">
            <header className="vp-panel-head">
              <h2 className="vp-panel-title">Facility Signals</h2>
              <span className="vp-panel-meta">Top {facilityPerformance.length || 3}</span>
            </header>
            {facilityPerformance.length === 0 ? (
              <div className="vp-empty">
                <span className="vp-empty-icon" aria-hidden>🏥</span>
                <h3 className="vp-empty-title">No facility data yet</h3>
                <p className="vp-empty-helper">
                  Once attempts are completed, ranked facilities will appear
                  here.
                </p>
              </div>
            ) : (
              <div className="vp-fac-list">
                {facilityPerformance.map((row) => {
                  const avg = row.averageScore;
                  const toneClass = facilityToneClass(avg);
                  return (
                    <div
                      key={row.facility}
                      className={["vp-fac-tile", toneClass].filter(Boolean).join(" ")}
                    >
                      <p className="vp-fac-name">{row.facility}</p>
                      <p className="vp-fac-meta">
                        {avg === null
                          ? "No average score recorded yet."
                          : `${Math.round(avg)}% average across ${row.completedAttempts} attempt(s).`}
                      </p>
                    </div>
                  );
                })}
              </div>
            )}
          </article>
        </section>
      </div>
    </AdminShell>
  );
}