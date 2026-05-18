import { AdminShell } from "@/components/admin-shell";
import { MetricCard } from "@/components/metric-card";
import { PanelCard } from "@/components/panel-card";

function barWidthClass(value: string): string {
  const map: Record<string, string> = {
    "61% correct": "w-[61%]",
    "68% correct": "w-[68%]",
    "72% correct": "w-[72%]",
    "75% correct": "w-[75%]",
  };

  return map[value] ?? "w-[50%]";
}

export default function DashboardPage() {
  return (
    <AdminShell
      title="Dashboard Overview"
      subtitle="Monitor pilot performance, participation quality, and the most immediate knowledge-gap signals."
      actions={
        <button className="arena-button bg-[var(--arena-primary)] px-5 py-3 font-semibold">
          Export Data
        </button>
      }
    >
      <section className="grid gap-5 xl:grid-cols-3">
        <MetricCard label="Join Rate" value="85%" delta="+5% versus last week" tone="primary" />
        <MetricCard label="Completion Rate" value="92%" delta="+2% versus last week" tone="secondary" />
        <MetricCard label="Average Score" value="78%" delta="-1% versus last week" tone="tertiary" />
      </section>
      <section className="grid gap-5 xl:grid-cols-[2fr_1fr]">
        <PanelCard title="Knowledge Gaps">
          <div className="space-y-4">
            {[
              ["Cardiology", "68% correct"],
              ["Neurology", "72% correct"],
              ["Pediatrics", "61% correct"],
              ["Respiratory", "75% correct"],
            ].map(([label, value]) => (
              <div key={label} className="flex items-center gap-4">
                <span className="w-28 font-semibold">{label}</span>
                <div className="h-4 flex-1 rounded-full border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface-muted)]">
                  <div className={["h-full rounded-full bg-[var(--arena-secondary)]", barWidthClass(value)].join(" ")} />
                </div>
                <span className="w-24 text-right text-sm text-[var(--arena-ink-muted)]">{value}</span>
              </div>
            ))}
          </div>
        </PanelCard>
        <PanelCard title="Recent Alerts">
          <div className="space-y-4">
            <div className="arena-panel bg-[var(--arena-danger)] p-4">
              <p className="font-semibold">Low engagement alert</p>
              <p className="mt-2 text-sm">Cohort B participation dropped below 60% this week.</p>
            </div>
            <div className="arena-panel bg-[var(--arena-surface)] p-4">
              <p className="font-semibold">New quiz published</p>
              <p className="mt-2 text-sm">Advanced Cardiology is now available for live sessions.</p>
            </div>
            <div className="arena-panel bg-[var(--arena-primary)] p-4">
              <p className="font-semibold">Milestone reached</p>
              <p className="mt-2 text-sm">10,000 questions answered across all pilot sessions.</p>
            </div>
          </div>
        </PanelCard>
      </section>
    </AdminShell>
  );
}