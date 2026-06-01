import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";
import { getAdminQuizDetailBySlug, getQuizOwnerBySlug } from "@/lib/quiz-detail-queries";

import { CsvExportButton } from "./csv-export-button";
import { CsvImportPanel } from "./csv-import-panel";
import { QuestionManager } from "./question-manager";
import { QuizEditForm } from "./quiz-edit-form";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = {
  params: Promise<{ slug: string }>;
  searchParams?: Promise<{
    focus?: string;
    imported?: string;
    failed?: string;
  }>;
};

function parseNonNegInt(raw: string | undefined): number | null {
  if (!raw) return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.floor(n);
}

export default async function QuizDetailPage({ params, searchParams }: PageProps) {
  const { slug } = await params;
  const sp = (await searchParams) ?? {};
  const focusQuestions = sp.focus === "questions";
  const importedCount = parseNonNegInt(sp.imported);
  const failedCount = parseNonNegInt(sp.failed);
  const session = await requireAdminSession({
    currentPath: `/quiz-bank/${slug}`,
  });

  // Host scoping: Hosts may browse the index, but only manage quizzes they
  // own. Owners can manage anything.
  if (session.role === "host") {
    const ownerId = await getQuizOwnerBySlug(slug);
    if (ownerId && ownerId !== session.userId) {
      redirect("/denied?reason=role");
    }
  }

  const user = { email: session.email, role: session.role };
  const backAction = (
    <span className="vp-scope">
      <Link href="/quiz-bank" className="vp-button vp-button-secondary">
        Back to Quiz Bank
      </Link>
    </span>
  );

  let detail;
  try {
    detail = await getAdminQuizDetailBySlug(slug);
  } catch (err) {
    return (
      <AdminShell
        title="Quiz Detail"
        subtitle="Edit metadata and manage questions."
        titleSize="sm"
        user={user}
        actions={backAction}
      >
        <div className="vp-scope">
          <div className="vp-card">
            <h2 className="vp-quiz-title">Unable to load quiz</h2>
            <p className="vp-quiz-summary">
              {err instanceof Error ? err.message : "Unknown error."}
            </p>
          </div>
        </div>
      </AdminShell>
    );
  }

  if (!detail) {
    notFound();
  }

  const { quiz, questions } = detail;

  return (
    <AdminShell
      title={quiz.title}
      subtitle={`Slug: ${quiz.slug} · ${quiz.isActive ? "Active" : "Inactive"} · ${questions.length} question${questions.length === 1 ? "" : "s"}`}
      titleSize="sm"
      user={user}
      actions={backAction}
    >
      <div className="vp-scope vp-vstack vp-vstack-lg">
        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Quiz Metadata</h2>
          </div>
          <QuizEditForm quiz={quiz} />
        </section>

        <section className="vp-panel" id="questions">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Questions</h2>
            <CsvExportButton quizSlug={quiz.slug} questions={questions} />
          </div>
          {focusQuestions ? (
            <div
              className={
                failedCount && failedCount > 0
                  ? "vp-banner vp-banner-error"
                  : "vp-banner vp-banner-info"
              }
              role="status"
            >
              {importedCount !== null ? (
                failedCount && failedCount > 0 ? (
                  <p>
                    Quiz created. Imported {importedCount} question
                    {importedCount === 1 ? "" : "s"}; {failedCount} row
                    {failedCount === 1 ? "" : "s"} failed — retry the failed rows
                    via the CSV Bulk Import panel below, or add questions
                    individually.
                  </p>
                ) : (
                  <p>
                    Quiz created and {importedCount} question
                    {importedCount === 1 ? "" : "s"} imported. Add or edit
                    individual questions below.
                  </p>
                )
              ) : questions.length === 0 ? (
                <p>
                  Quiz created. Add your first question below, or jump to the
                  CSV Bulk Import panel to upload many at once.
                </p>
              ) : (
                <p>
                  Quiz created. Add more questions below or import a CSV.
                </p>
              )}
            </div>
          ) : null}
          <QuestionManager quizId={quiz.id} quizSlug={quiz.slug} questions={questions} />
        </section>

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">CSV Bulk Import</h2>
          </div>
          <CsvImportPanel quizId={quiz.id} quizSlug={quiz.slug} />
        </section>
      </div>
    </AdminShell>
  );
}
