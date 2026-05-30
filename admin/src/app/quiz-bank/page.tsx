import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
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
      titleSize="sm"
      user={{ email: session.email, role: session.role }}
      actions={
        <Link href="/quiz-bank/new" className="vp-button vp-button-primary">
          Create New Quiz
        </Link>
      }
      filters={<ScopeToggle current={scope} label="Show" />}
    >
      <div className="vp-scope">
        {loadError ? (
          <div className="vp-card">
            <h2 className="vp-quiz-title">Unable to load quizzes</h2>
            <p className="vp-quiz-summary">{loadError}</p>
            <p className="vp-meta-row vp-mt-3">
              <span>
                Check that SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
                configured for this environment.
              </span>
            </p>
          </div>
        ) : quizzes.length === 0 ? (
          <div className="vp-empty">
            <div className="vp-empty-icon">📚</div>
            <h2 className="vp-empty-title">No quizzes yet</h2>
            <p className="vp-empty-helper">
              Seed quizzes via supabase/seed or wait until the create flow ships.
            </p>
          </div>
        ) : (
          <div className="vp-list">
            <div className="vp-list-utility-row">
              <button
                type="button"
                className="vp-link-ghost"
                disabled
                title="Bulk upload pipeline ships in a follow-up commit."
              >
                + Bulk import via CSV
              </button>
            </div>
            {quizzes.map((quiz) => {
              const canManage =
                session.role === "owner" || quiz.createdBy === session.userId;
              return (
                <article key={quiz.id} className="vp-quiz-card">
                  <div className="vp-quiz-card-head">
                    <div>
                      <span className="vp-tag">
                        {quiz.category || "Uncategorized"}
                      </span>
                      <h2 className="vp-quiz-title">{quiz.title}</h2>
                      {quiz.summary ? (
                        <p className="vp-quiz-summary">{quiz.summary}</p>
                      ) : null}
                      <div className="vp-meta-row vp-mt-4">
                        <span>slug · {quiz.slug}</span>
                        {quiz.product ? <span>product · {quiz.product}</span> : null}
                        <span>{quiz.isActive ? "active" : "inactive"}</span>
                      </div>
                    </div>
                    <div className="vp-quiz-side">
                      <p className="vp-quiz-count">
                        {quiz.questionCount} Question
                        {quiz.questionCount === 1 ? "" : "s"}
                      </p>
                      {canManage ? (
                        <Link
                          href={`/quiz-bank/${quiz.slug}`}
                          className="vp-button vp-button-primary"
                        >
                          Manage
                        </Link>
                      ) : (
                        <span
                          title="Hosts can only manage quizzes they created."
                          className="vp-button vp-button-secondary vp-disabled-soft"
                        >
                          View only
                        </span>
                      )}
                    </div>
                  </div>
                  {quiz.sampleQuestions.length > 0 ? (
                    <div className="vp-sample-list">
                      {quiz.sampleQuestions.map((prompt, index) => (
                        <div
                          key={`${quiz.id}-${index}`}
                          className="vp-sample-row"
                        >
                          <p className="vp-sample-id">Q-{101 + index}</p>
                          <p className="vp-sample-text">{prompt}</p>
                        </div>
                      ))}
                    </div>
                  ) : null}
                </article>
              );
            })}
          </div>
        )}
      </div>
    </AdminShell>
  );
}