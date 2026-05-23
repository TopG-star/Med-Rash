import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { MetricCard } from "@/components/metric-card";
import { PanelCard } from "@/components/panel-card";
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

export default async function DashboardPage() {
  const session = await requireAdminSession({ currentPath: "/dashboard" });
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
      getOverviewKpis(),
      getMostMissed(4),
      getFacilityPerformance(3),
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
        <a
          className="arena-button bg-[var(--arena-primary)] px-5 py-3 font-semibold"
          href="/reports"
        >
          Open Reports
        </a>
      }
    >
      {loadError && (
        <section className="arena-panel border-[var(--arena-danger)] bg-[var(--arena-danger)] p-4">
          <p className="font-semibold">Dashboard data unavailable</p>
          <p className="mt-2 text-sm">{loadError}</p>
        </section>
      )}
      <section className="grid gap-5 xl:grid-cols-3">
        <MetricCard
          label="Total Participants"
          value={kpis.totalUsers.toLocaleString()}
          delta={`${kpis.activeQuizzes} active quizzes`}
          tone="primary"
        />
        <MetricCard
          label="Completed Attempts"
          value={kpis.completedAttempts.toLocaleString()}
          delta={completionDelta}
          tone="secondary"
        />
        <MetricCard
          label="Average Score"
          value={formatPercent(kpis.averageScorePercent)}
          delta="Rolling 30-day window"
          tone="tertiary"
        />
      </section>
      <section className="grid gap-5 xl:grid-cols-[2fr_1fr]">
        <PanelCard title="Most-Missed Questions">
          {mostMissed.length === 0 ? (
            <EmptyState
              icon={<span>📊</span>}
              title="No answer data yet"
              helper="Once your first participant submits, this panel will populate within seconds."
            />
          ) : (
            <div className="space-y-4">
              {mostMissed.map((row) => {
                const wrongPercent = clampPercent(row.incorrectRate);
                return (
                  <div key={row.questionId} className="flex items-center gap-4">
                    <span className="w-40 font-semibold" title={row.quizTitle}>
                      {truncate(row.quizTitle || "(quiz)", 22)}
                    </span>
                    <div
                      className="h-4 flex-1 rounded-full border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface-muted)]"
                      title={row.prompt}
                    >
                      <div
                        className={["h-full rounded-full bg-[var(--arena-secondary)]", widthClassFromPercent(wrongPercent)].join(" ")}
                      />
                    </div>
                    <span className="w-32 text-right text-sm text-[var(--arena-ink-muted)]">
                      {wrongPercent}% wrong
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </PanelCard>
        <PanelCard title="Facility Signals">
          {facilityPerformance.length === 0 ? (
            <EmptyState
              icon={<span>🏥</span>}
              title="No facility data yet"
              helper="Once attempts are completed, ranked facilities will appear here."
            />
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
                        : `${Math.round(avg)}% average across ${row.completedAttempts} attempt(s).`}
                    </p>
                  </div>
                );
              })}
            </div>
          )}
        </PanelCard>
      </section>
    </AdminShell>
  );
}