import { AdminShell } from "@/components/admin-shell";
import { MetricCard } from "@/components/metric-card";
import { PanelCard } from "@/components/panel-card";
import { requireOwner } from "@/lib/admin-session";
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
  const session = await requireOwner({ currentPath: "/intelligence" });
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
      getOverviewKpis(),
      getMostMissed(6),
      getFacilityPerformance(5),
      getTreatmentPerception(3),
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
        <a
          className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold"
          href="/reports"
        >
          Open Reports
        </a>
      }
    >
      {loadError && (
        <section className="arena-panel border-[var(--arena-danger)] bg-[var(--arena-danger)] p-4">
          <p className="font-semibold">Intelligence data unavailable</p>
          <p className="mt-2 text-sm">{loadError}</p>
        </section>
      )}
      <section className="grid gap-5 xl:grid-cols-3">
        <MetricCard
          label="Average Score"
          value={formatPercent(kpis.averageScorePercent)}
          delta="Rolling 30-day window"
          tone="primary"
        />
        <MetricCard
          label="Total Users"
          value={kpis.totalUsers.toLocaleString()}
          delta={`${kpis.completedAttempts.toLocaleString()} completed attempts`}
          tone="secondary"
        />
        <MetricCard
          label="Top Gap Area"
          value={topGap ? truncate(topGap.prompt, 28) : "\u2014"}
          delta={topGap ? `${clampPercent(topGap.incorrectRate)}% error rate` : "No data yet"}
          tone="tertiary"
        />
      </section>
      <section className="grid gap-5 xl:grid-cols-[1.3fr_1fr]">
        <PanelCard title="Most-Missed Questions">
          {mostMissed.length === 0 ? (
            <p className="text-sm text-[var(--arena-ink-muted)]">
              No answer data yet. Run a session to populate this panel.
            </p>
          ) : (
            <div className="space-y-5">
              {mostMissed.map((row) => {
                const wrongPercent = clampPercent(row.incorrectRate);
                return (
                  <div key={row.questionId} className="space-y-2">
                    <p className="font-semibold">{truncate(row.prompt, 90)}</p>
                    <p className="text-xs text-[var(--arena-ink-muted)]">
                      {row.quizTitle}{" \u00b7 "}{row.incorrectCount}/{row.attemptsCount} wrong
                    </p>
                    <div className="flex items-center gap-3">
                      <div className="h-4 flex-1 rounded-full bg-[var(--arena-panel)]">
                        <div
                          className={["h-full rounded-full bg-[var(--arena-secondary)]", widthClassFromPercent(wrongPercent)].join(" ")}
                        />
                      </div>
                      <span className="w-14 text-right text-sm">{wrongPercent}%</span>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </PanelCard>
        <div className="grid gap-5">
          <PanelCard title="Facility Performance Heatmap">
            {facilityPerformance.length === 0 ? (
              <p className="text-sm text-[var(--arena-ink-muted)]">
                No completed attempts to rank facilities yet.
              </p>
            ) : (
              <div className="space-y-3">
                {facilityPerformance.map((row) => {
                  const avg = row.averageScore;
                  const tone =
                    avg === null
                      ? "bg-[var(--arena-surface)]"
                      : avg < 60
                        ? "bg-[var(--arena-danger)]"
                        : avg < 80
                          ? "bg-[var(--arena-primary)]"
                          : "bg-[var(--arena-surface)]";
                  return (
                    <div key={row.facility} className={`arena-panel ${tone} p-4`}>
                      <p className="font-semibold">{row.facility}</p>
                      <p className="mt-2 text-sm">
                        {avg === null
                          ? "No average score recorded yet."
                          : `${Math.round(avg)}% average \u00b7 ${row.completedAttempts} attempt(s) \u00b7 ${row.rankedParticipants} ranked`}
                      </p>
                    </div>
                  );
                })}
              </div>
            )}
          </PanelCard>
          <PanelCard title="Treatment Perception Trends">
            {treatmentPerception.length === 0 ? (
              <p className="text-sm text-[var(--arena-ink-muted)]">
                No treatment-perception signals yet. Tag questions with
                {' '}<code>treatment-perception</code> to surface them here.
              </p>
            ) : (
              <div className="space-y-4 text-sm leading-7 text-[var(--arena-ink-muted)]">
                {treatmentPerception.map((row, index) => {
                  const wrongPercent = clampPercent(row.incorrectRate);
                  return (
                    <p key={`${row.prompt}-${index}`}>
                      <span className="font-semibold text-[var(--arena-ink)]">
                        {wrongPercent}%
                      </span>{" "}
                      of respondents{row.clinicalArea ? ` in ${row.clinicalArea}` : ""} picked
                      {" "}<span className="italic">{truncate(row.mostSelectedWrongOption, 40)}</span>{" "}
                      when asked: {truncate(row.prompt, 110)}
                    </p>
                  );
                })}
              </div>
            )}
          </PanelCard>
        </div>
      </section>
    </AdminShell>
  );
}