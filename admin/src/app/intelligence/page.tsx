import { AdminShell } from "@/components/admin-shell";
import { MetricCard } from "@/components/metric-card";
import { PanelCard } from "@/components/panel-card";

function percentWidthClass(percent: string): string {
  const map: Record<string, string> = {
    "85%": "w-[85%]",
    "92%": "w-[92%]",
    "78%": "w-[78%]",
    "65%": "w-[65%]",
  };

  return map[percent] ?? "w-[50%]";
}

export default function IntelligencePage() {
  return (
    <AdminShell
      title="Intelligence"
      subtitle="Deep-dive into knowledge gaps, facility performance, and treatment perception patterns surfaced by answer-level analytics."
      actions={
        <button className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold">
          Export CSV
        </button>
      }
    >
      <section className="grid gap-5 xl:grid-cols-3">
        <MetricCard label="Average Score" value="78%" delta="+4% versus last month" tone="primary" />
        <MetricCard label="Total Users" value="1,240" delta="890 active this week" tone="secondary" />
        <MetricCard label="Top Gap Area" value="Pediatric Dosage" delta="42% error rate" tone="tertiary" />
      </section>
      <section className="grid gap-5 xl:grid-cols-[1.3fr_1fr]">
        <PanelCard title="Knowledge Gaps By Specialty">
          <div className="space-y-5">
            {[
              ["Infection Control Protocols", "85%", "92%"],
              ["Emergency Trauma Response", "78%", "65%"],
            ].map(([topic, doctors, nurses]) => (
              <div key={topic} className="space-y-2">
                <p className="font-semibold">{topic}</p>
                <div className="space-y-2">
                  <div className="flex items-center gap-3">
                    <span className="w-16 text-sm">Doctors</span>
                    <div className="h-4 flex-1 rounded-full bg-[var(--arena-panel)]">
                      <div className={["h-full rounded-full bg-cyan-700", percentWidthClass(doctors)].join(" ")} />
                    </div>
                    <span className="w-14 text-right text-sm">{doctors}</span>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="w-16 text-sm">Nurses</span>
                    <div className="h-4 flex-1 rounded-full bg-[var(--arena-panel)]">
                      <div className={["h-full rounded-full bg-fuchsia-600", percentWidthClass(nurses)].join(" ")} />
                    </div>
                    <span className="w-14 text-right text-sm">{nurses}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </PanelCard>
        <div className="grid gap-5">
          <PanelCard title="Facility Performance Heatmap">
            <div className="space-y-3">
              <div className="arena-panel bg-[var(--arena-danger)] p-4">
                <p className="font-semibold">Korle-Bu Teaching Hospital</p>
                <p className="mt-2 text-sm">45% critical gap in maternal health module</p>
              </div>
              <div className="arena-panel bg-[var(--arena-primary)] p-4">
                <p className="font-semibold">Komfo Anokye Teaching Hospital</p>
                <p className="mt-2 text-sm">62% needs review in pharmacology module</p>
              </div>
              <div className="arena-panel bg-[var(--arena-surface)] p-4">
                <p className="font-semibold">Tamale Teaching Hospital</p>
                <p className="mt-2 text-sm">88% on track in cardiology module</p>
              </div>
            </div>
          </PanelCard>
          <PanelCard title="Treatment Perception Trends">
            <div className="space-y-4 text-sm leading-7 text-[var(--arena-ink-muted)]">
              <p>
                Based on recent quiz scenarios, 35% of rural facility respondents incorrectly selected broad-spectrum antibiotics as a first-line treatment for viral-presenting symptoms.
              </p>
              <p>
                Nurses show a 20% higher post-operative pain-management accuracy than junior doctors in the last 30 days, especially in opioid titration decisions.
              </p>
            </div>
          </PanelCard>
        </div>
      </section>
    </AdminShell>
  );
}