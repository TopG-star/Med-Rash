import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";
import { getAdminQuizDetailBySlug, getQuizOwnerBySlug } from "@/lib/quiz-detail-queries";

import { CsvImportPanel } from "./csv-import-panel";
import { QuestionManager } from "./question-manager";
import { QuizEditForm } from "./quiz-edit-form";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = { params: Promise<{ slug: string }> };

export default async function QuizDetailPage({ params }: PageProps) {
  const { slug } = await params;
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

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Questions</h2>
          </div>
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
