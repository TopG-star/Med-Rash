import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";

const quizGroups = [
  {
    category: "Cardiology",
    title: "Advanced ECG Interpretation",
    count: 15,
    questions: [
      "What is the most common cause of a wide complex tachycardia?",
      "Identify the rhythm shown in the attached tracing.",
    ],
  },
  { category: "Emergency", title: "Trauma Resuscitation Protocols", count: 22, questions: [] },
  { category: "Pharmacology", title: "Antibiotic Stewardship Basics", count: 10, questions: [] },
];

export default function QuizBankPage() {
  return (
    <AdminShell
      title="Quiz Bank Management"
      subtitle="Manage approved medical quizzes, question sets, and upload-ready content for live sessions and self-paced play."
      actions={
        <>
          <button className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold">Bulk Upload (CSV)</button>
          <button className="arena-button bg-[var(--arena-primary)] px-5 py-3 font-semibold">Create New Quiz</button>
        </>
      }
    >
      <div className="space-y-5">
        {quizGroups.map((group) => (
          <PanelCard key={group.title} className="space-y-4">
            <div className="flex items-start justify-between gap-4">
              <div>
                <span className="inline-flex rounded-full border-[2px] border-[var(--arena-outline)] bg-[var(--arena-secondary)] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.05em]">
                  {group.category}
                </span>
                <h2 className="mt-3 font-[family-name:var(--font-anybody)] text-3xl font-extrabold tracking-tight">
                  {group.title}
                </h2>
              </div>
              <p className="text-sm font-semibold text-[var(--arena-ink-muted)]">{group.count} Questions</p>
            </div>
            {group.questions.length > 0 ? (
              <div className="overflow-hidden rounded-[16px] border-[3px] border-[var(--arena-outline)]">
                {group.questions.map((question, index) => (
                  <div key={question} className="flex items-center justify-between gap-4 border-b-[2px] border-[var(--arena-outline-muted)] bg-[var(--arena-surface)] px-4 py-4 last:border-b-0">
                    <div>
                      <p className="text-xs font-extrabold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">Q-{101 + index}</p>
                      <p className="mt-1 font-medium">{question}</p>
                    </div>
                    <div className="flex gap-2">
                      <button className="arena-button bg-[var(--arena-surface)] px-3 py-2 text-sm font-semibold">Edit</button>
                      <button className="arena-button bg-[var(--arena-danger)] px-3 py-2 text-sm font-semibold">Delete</button>
                    </div>
                  </div>
                ))}
              </div>
            ) : null}
          </PanelCard>
        ))}
      </div>
    </AdminShell>
  );
}