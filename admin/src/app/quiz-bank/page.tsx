import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";
import { ScopeToggle, type ScopeValue } from "@/components/scope-toggle";
import { requireAdminSession } from "@/lib/admin-session";
import { listAdminQuizzes, type AdminQuizSummary } from "@/lib/quiz-bank-queries";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = { scope?: string };

function parseScope(raw: string | undefined): ScopeValue {
  return raw === "all" ? "all" : "mine";
}

export default async function QuizBankPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const session = await requireAdminSession({ currentPath: "/quiz-bank" });
  const sp = await searchParams;
  const scope = parseScope(sp.scope);

  let quizzes: AdminQuizSummary[] = [];
  let loadError: string | null = null;

  try {
    quizzes = await listAdminQuizzes({ scope, userId: session.userId });
  } catch (err) {
    loadError = err instanceof Error ? err.message : "Failed to load quizzes.";
  }

  return (
    <AdminShell
      title="Quiz Bank Management"
      subtitle="Manage approved medical quizzes, question sets, and upload-ready content for live sessions and self-paced play."
      user={{ email: session.email, role: session.role }}
      actions={
        <>
          <ScopeToggle current={scope} label="Show" />
          <button
            className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold opacity-60"
            disabled
            title="Bulk upload pipeline ships in a follow-up commit."
          >
            Bulk Upload (CSV)
          </button>
          <Link
            href="/quiz-bank/new"
            className="arena-button bg-[var(--arena-primary)] px-5 py-3 font-semibold"
          >
            Create New Quiz
          </Link>
        </>
      }
    >
      {loadError ? (
        <PanelCard className="space-y-2">
          <h2 className="font-[family-name:var(--font-anybody)] text-xl font-extrabold uppercase tracking-tight">
            Unable to load quizzes
          </h2>
          <p className="text-sm font-medium text-[var(--arena-ink-muted)]">
            {loadError}
          </p>
          <p className="text-xs font-semibold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            Check that SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are configured for this environment.
          </p>
        </PanelCard>
      ) : quizzes.length === 0 ? (
        <PanelCard className="space-y-2">
          <h2 className="font-[family-name:var(--font-anybody)] text-xl font-extrabold uppercase tracking-tight">
            No quizzes yet
          </h2>
          <p className="text-sm font-medium text-[var(--arena-ink-muted)]">
            Seed quizzes via supabase/seed or wait until the create flow ships.
          </p>
        </PanelCard>
      ) : (
        <div className="space-y-5">
          {quizzes.map((quiz) => (
            <PanelCard key={quiz.id} className="space-y-4">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <span className="inline-flex rounded-full border-[2px] border-[var(--arena-outline)] bg-[var(--arena-secondary)] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.05em]">
                    {quiz.category || "Uncategorized"}
                  </span>
                  <h2 className="mt-3 font-[family-name:var(--font-anybody)] text-3xl font-extrabold tracking-tight">
                    {quiz.title}
                  </h2>
                  {quiz.summary ? (
                    <p className="mt-2 max-w-2xl text-sm font-medium text-[var(--arena-ink-muted)]">
                      {quiz.summary}
                    </p>
                  ) : null}
                  <div className="mt-3 flex flex-wrap items-center gap-2 text-xs font-semibold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
                    <span>slug · {quiz.slug}</span>
                    {quiz.product ? <span>product · {quiz.product}</span> : null}
                    <span>{quiz.isActive ? "active" : "inactive"}</span>
                  </div>
                </div>
                <div className="flex flex-col items-end gap-2">
                  <p className="text-sm font-semibold text-[var(--arena-ink-muted)]">
                    {quiz.questionCount} Question{quiz.questionCount === 1 ? "" : "s"}
                  </p>
                  <Link
                    href={`/quiz-bank/${quiz.slug}`}
                    className="arena-button bg-[var(--arena-surface)] px-4 py-2 text-sm font-semibold"
                  >
                    Manage
                  </Link>
                </div>
              </div>
              {quiz.sampleQuestions.length > 0 ? (
                <div className="overflow-hidden rounded-[16px] border-[3px] border-[var(--arena-outline)]">
                  {quiz.sampleQuestions.map((prompt, index) => (
                    <div
                      key={`${quiz.id}-${index}`}
                      className="flex items-center justify-between gap-4 border-b-[2px] border-[var(--arena-outline-muted)] bg-[var(--arena-surface)] px-4 py-4 last:border-b-0"
                    >
                      <div>
                        <p className="text-xs font-extrabold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
                          Q-{101 + index}
                        </p>
                        <p className="mt-1 font-medium">{prompt}</p>
                      </div>
                    </div>
                  ))}
                </div>
              ) : null}
            </PanelCard>
          ))}
        </div>
      )}
    </AdminShell>
  );
}