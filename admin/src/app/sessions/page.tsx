import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";

const activeSessions = [
  { name: "Cardiology Basics - Cohort A", end: "Oct 25, 2026", participants: 45, active: true },
  { name: "Emergency Protocols v2", end: "Nov 02, 2026", participants: 112, active: true },
  { name: "Pharmacology Midterm", end: "Sep 15, 2026", participants: 89, active: false },
];

export default function SessionsPage() {
  return (
    <AdminShell
      title="Sessions"
      subtitle="Create live sessions, attach an approved quiz, and generate QR-linked access for presentation or CME use."
    >
      <section className="grid gap-5 xl:grid-cols-[1.5fr_1fr]">
        <PanelCard title="Create New Session">
          <div className="grid gap-4 md:grid-cols-2">
            <label className="md:col-span-2 space-y-2">
              <span className="text-sm font-semibold">Session Name</span>
              <input className="arena-panel w-full px-4 py-3" defaultValue="Q3 Cardiology Review" />
            </label>
            <label className="md:col-span-2 space-y-2">
              <span className="text-sm font-semibold">Select Quiz</span>
              <select className="arena-panel w-full px-4 py-3">
                <option>Cardiology Basics</option>
                <option>Advanced ECG Interpretation</option>
                <option>Antibiotic Stewardship Basics</option>
              </select>
            </label>
            <label className="space-y-2">
              <span className="text-sm font-semibold">Start Date</span>
              <input className="arena-panel w-full px-4 py-3" placeholder="mm/dd/yyyy" />
            </label>
            <label className="space-y-2">
              <span className="text-sm font-semibold">End Date</span>
              <input className="arena-panel w-full px-4 py-3" placeholder="mm/dd/yyyy" />
            </label>
            <button className="arena-button md:col-span-2 bg-[var(--arena-primary)] px-5 py-4 font-semibold">
              Generate Link &amp; QR
            </button>
          </div>
        </PanelCard>
        <PanelCard title="Preview Area">
          <div className="flex min-h-72 flex-col items-center justify-center rounded-[16px] bg-[var(--arena-panel)] p-6 text-center">
            <div className="h-24 w-24 rounded-[16px] border-[3px] border-dashed border-[var(--arena-outline)] bg-[var(--arena-surface)]" />
            <p className="mt-4 font-semibold">Generate a session to preview the QR code and join link.</p>
          </div>
        </PanelCard>
      </section>
      <PanelCard title="Active Sessions">
        <div className="space-y-4">
          {activeSessions.map((session) => (
            <div key={session.name} className="arena-panel flex flex-col gap-4 bg-[var(--arena-surface)] p-4 md:flex-row md:items-center md:justify-between">
              <div>
                <div className="flex items-center gap-2">
                  <span className={`h-3 w-3 rounded-full ${session.active ? "bg-green-500" : "bg-red-400"}`} />
                  <p className="font-semibold">{session.name}</p>
                </div>
                <p className="mt-2 text-sm text-[var(--arena-ink-muted)]">
                  Ends: {session.end} • {session.participants} participants
                </p>
              </div>
              <div className="flex gap-3">
                <button className="arena-button bg-[var(--arena-secondary)] px-4 py-2 text-sm font-semibold">Share</button>
                <button className="arena-button bg-[var(--arena-primary)] px-4 py-2 text-sm font-semibold">Export Data</button>
              </div>
            </div>
          ))}
        </div>
      </PanelCard>
    </AdminShell>
  );
}