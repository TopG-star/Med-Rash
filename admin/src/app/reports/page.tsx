import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";

const previousExports = [
  { title: "Weekly Usage Stats", date: "Oct 24, 2026", type: "CSV" },
  { title: "Q3 Detailed Answers Dump", date: "Oct 01, 2026", type: "Excel" },
  { title: "All Users Demographics", date: "Sep 15, 2026", type: "CSV" },
];

export default function ReportsPage() {
  return (
    <AdminShell
      title="Reports"
      subtitle="Generate operational and intelligence exports for pilot review, stakeholder reporting, and follow-up analysis."
    >
      <PanelCard title="Generate New Report">
        <div className="grid gap-4 md:grid-cols-2">
          <label className="space-y-2 md:col-span-2">
            <span className="text-sm font-semibold">Select Data To Include</span>
            <div className="flex flex-wrap gap-3">
              {['All Attempts', 'Detailed Answers', 'User Demographics'].map((item, index) => (
                <label key={item} className="arena-panel flex items-center gap-2 bg-[var(--arena-surface)] px-4 py-3">
                  <input type="checkbox" defaultChecked={index < 2} />
                  <span>{item}</span>
                </label>
              ))}
            </div>
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Start Date</span>
            <input className="arena-panel w-full px-4 py-3" placeholder="mm/dd/yyyy" />
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">End Date</span>
            <input className="arena-panel w-full px-4 py-3" placeholder="mm/dd/yyyy" />
          </label>
          <div className="space-y-2 md:col-span-2">
            <span className="text-sm font-semibold">Export Format</span>
            <div className="grid gap-4 md:grid-cols-2">
              <button className="arena-button bg-[var(--arena-secondary)] px-4 py-8 font-semibold">CSV</button>
              <button className="arena-button bg-[var(--arena-surface)] px-4 py-8 font-semibold">Excel</button>
            </div>
          </div>
          <button className="arena-button md:col-span-2 bg-[var(--arena-primary)] px-5 py-4 font-semibold">
            Generate Report
          </button>
        </div>
      </PanelCard>
      <PanelCard title="Previous Exports">
        <div className="space-y-4">
          {previousExports.map((item) => (
            <div key={item.title} className="arena-panel flex flex-col gap-3 bg-[var(--arena-surface)] p-4 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="font-semibold">{item.title}</p>
                <p className="mt-1 text-sm text-[var(--arena-ink-muted)]">{item.date} • {item.type}</p>
              </div>
              <button className="arena-button bg-[var(--arena-secondary)] px-4 py-2 text-sm font-semibold">Download</button>
            </div>
          ))}
        </div>
      </PanelCard>
    </AdminShell>
  );
}