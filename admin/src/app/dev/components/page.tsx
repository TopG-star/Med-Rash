import { notFound } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { MetricCard } from "@/components/metric-card";
import { PanelCard } from "@/components/panel-card";

export const dynamic = "force-dynamic";

const DEV_USER = { email: "dev@medrash.local", role: "owner" as const };

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="vp-scope flex flex-col gap-3">
      <h2 className="vp-display vp-display-accent text-xl">{title}</h2>
      {children}
    </section>
  );
}

export default function DevComponentsPage() {
  if (process.env.NODE_ENV === "production") {
    notFound();
  }

  return (
    <AdminShell
      title="Component catalog"
      subtitle="Dev-only preview of admin primitives. Hidden from production builds."
      user={DEV_USER}
    >
      <div className="vp-scope flex flex-col gap-8">
        <Section title="MetricCard">
          <div className="grid gap-4 md:grid-cols-3">
            <MetricCard
              label="Total participants"
              value="1,284"
              delta="+12% vs last week"
              subtitle="Pilot cohort A"
              tone="primary"
            />
            <MetricCard
              label="Avg score"
              value="78%"
              delta="+3 pts"
              tone="secondary"
            />
            <MetricCard
              label="Active quizzes"
              value="9"
              delta="2 launching today"
              tone="tertiary"
            />
          </div>
        </Section>

        <Section title="PanelCard">
          <PanelCard title="Sample panel">
            <p className="text-sm">
              Panel cards group related stats and tables inside the admin shell.
            </p>
          </PanelCard>
        </Section>

        <Section title="EmptyState">
          <EmptyState
            title="No reports yet"
            helper="Once the first ranked session closes, its analytics will land here."
            action={
              <a className="vp-button vp-button-primary" href="#">
                Create session
              </a>
            }
          />
        </Section>

        <Section title="Buttons">
          <div className="flex flex-wrap gap-3">
            <button className="vp-button vp-button-primary" type="button">
              Primary action
            </button>
            <button className="vp-button vp-button-ghost" type="button">
              Ghost action
            </button>
          </div>
        </Section>

        <Section title="Dark scope (.host-room-dark)">
          <div className="host-room-dark vp-scope rounded-3xl p-6">
            <p className="text-sm">
              Scoped dark surface used by the host control room. App-wide dark
              mode is on the roadmap — see <code>docs/design-architecture.md</code>.
            </p>
          </div>
        </Section>
      </div>
    </AdminShell>
  );
}
