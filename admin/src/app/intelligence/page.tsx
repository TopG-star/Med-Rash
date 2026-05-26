import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";
import { getOverviewKpis } from "@/lib/overview-queries";
import {
  getFacilityPerformance,
  getMostMissed,
  getTreatmentPerception,
} from "@/lib/reports-queries";
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

export default async function IntelligencePage() {
  const session = await requireAdminSession({ currentPath: "/intelligence" });
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
  let treatmentPerception: Awaited<ReturnType<typeof getTreatmentPerception>> = [];

  try {
    [kpis, mostMissed, facilityPerformance, treatmentPerception] = await Promise.all([
      getOverviewKpis({ createdBy }),
      getMostMissed(6, {}, { createdBy }),
      getFacilityPerformance(5, { createdBy }),
      getTreatmentPerception(3, { createdBy }),
    ]);
  } catch (error) {
    loadError = error instanceof Error ? error.message : "Failed to load intelligence data.";
  }

  const topGap = mostMissed[0] ?? null;

  return (
    <AdminShell
      title="Intelligence"
      subtitle="Deep-dive into knowledge gaps, facility performance, and treatment perception patterns surfaced by answer-level analytics."
      user={{ email: session.email, role: session.role }}
      actions={
        <span className="vp-scope">
          <a className="vp-button vp-button-ghost vp-button-sm" href="/reports">
            Open Reports
          </a>
        </span>
      }
    >
      <div className="vp-scope vp-vstack vp-vstack-lg">
        {loadError && (
          <div className="vp-banner vp-banner-error">
            <p>
              <strong>Intelligence data unavailable.</strong> {loadError}
            </p>
          </div>
        )}

        <section className="vp-stat-grid">
          <div className="vp-stat-tile">
            <span className="vp-stat-label">Average Score</span>
            <span className="vp-stat-value">
              {formatPercent(kpis.averageScorePercent)}
            </span>
            <span className="vp-stat-delta">Rolling 30-day window</span>
          </div>
          <div className="vp-stat-tile">
            <span className="vp-stat-label">Total Users</span>
            <span className="vp-stat-value">
              {kpis.totalUsers.toLocaleString()}
            </span>
            <span className="vp-stat-delta">
              {kpis.completedAttempts.toLocaleString()} completed attempts
            </span>
          </div>
          <div className="vp-stat-tile">
            <span className="vp-stat-label">Top Gap Area</span>
            <span className="vp-stat-value">
              {topGap ? truncate(topGap.prompt, 28) : "\u2014"}
            </span>
            <span className="vp-stat-delta">
              {topGap
                ? `${clampPercent(topGap.incorrectRate)}% error rate`
                : "No data yet"}
            </span>
          </div>
        </section>

        <section className="vp-split-grid">
          <div className="vp-panel">
            <div className="vp-panel-head">
              <h2 className="vp-panel-title">Most-Missed Questions</h2>
            </div>
            {mostMissed.length === 0 ? (
              <div className="vp-empty">
                <div aria-hidden="true" className="vp-empty-icon">🔍</div>
                <h3 className="vp-empty-title">No answer data yet</h3>
                <p className="vp-empty-helper">
                  Run a session to populate this panel.
                </p>
              </div>
            ) : (
              <div className="vp-vstack-md">
                {mostMissed.map((row) => {
                  const wrongPercent = clampPercent(row.incorrectRate);
                  return (
                    <div key={row.questionId} className="vp-intel-row">
                      <p className="vp-preview-prompt">
                        {truncate(row.prompt, 90)}
                      </p>
                      <p className="vp-preview-meta">
                        {row.quizTitle}
                        {" \u00b7 "}
                        {row.incorrectCount}/{row.attemptsCount} wrong
                      </p>
                      <div className="vp-intel-bar-row">
                        <div aria-hidden="true" className="vp-bar">
                          <div
                            className={[
                              "vp-bar-fill",
                              widthClassFromPercent(wrongPercent),
                            ].join(" ")}
                          />
                        </div>
                        <span className="vp-intel-bar-value">
                          {wrongPercent}%
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          <div className="vp-vstack vp-vstack-lg">
            <div className="vp-panel">
              <div className="vp-panel-head">
                <h2 className="vp-panel-title">Facility Performance Heatmap</h2>
              </div>
              {facilityPerformance.length === 0 ? (
                <div className="vp-empty">
                  <div aria-hidden="true" className="vp-empty-icon">🏥</div>
                  <h3 className="vp-empty-title">No facility data</h3>
                  <p className="vp-empty-helper">
                    No completed attempts to rank facilities yet.
                  </p>
                </div>
              ) : (
                <div className="vp-fac-list">
                  {facilityPerformance.map((row) => {
                    const avg = row.averageScore;
                    const tone =
                      avg === null
                        ? ""
                        : avg < 60
                          ? "is-danger"
                          : avg < 80
                            ? "is-warn"
                            : "is-success";
                    return (
                      <div
                        key={row.facility}
                        className={`vp-fac-tile ${tone}`.trim()}
                      >
                        <p className="vp-fac-name">{row.facility}</p>
                        <p className="vp-fac-meta">
                          {avg === null
                            ? "No average score recorded yet."
                            : `${Math.round(avg)}% average \u00b7 ${row.completedAttempts} attempt(s) \u00b7 ${row.rankedParticipants} ranked`}
                        </p>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            <div className="vp-panel">
              <div className="vp-panel-head">
                <h2 className="vp-panel-title">Treatment Perception Trends</h2>
              </div>
              {treatmentPerception.length === 0 ? (
                <div className="vp-empty">
                  <div aria-hidden="true" className="vp-empty-icon">💊</div>
                  <h3 className="vp-empty-title">No signals yet</h3>
                  <p className="vp-empty-helper">
                    Tag questions with <code>treatment-perception</code> to
                    surface them here.
                  </p>
                </div>
              ) : (
                <div className="vp-trend-list">
                  {treatmentPerception.map((row, index) => {
                    const wrongPercent = clampPercent(row.incorrectRate);
                    return (
                      <p key={`${row.prompt}-${index}`}>
                        <span className="vp-trend-stat">{wrongPercent}%</span>{" "}
                        of respondents
                        {row.clinicalArea ? ` in ${row.clinicalArea}` : ""}{" "}
                        picked{" "}
                        <span className="vp-trend-quote">
                          {truncate(row.mostSelectedWrongOption, 40)}
                        </span>{" "}
                        when asked: {truncate(row.prompt, 110)}
                      </p>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </section>
      </div>
    </AdminShell>
  );
}
