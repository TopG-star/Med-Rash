import Link from "next/link";
import { notFound } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";
import { getAdminQuizDetailBySlug } from "@/lib/quiz-detail-queries";

import { QuestionManager } from "./question-manager";
import { QuizEditForm } from "./quiz-edit-form";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = { params: Promise<{ slug: string }> };

export default async function QuizDetailPage({ params }: PageProps) {
  const { slug } = await params;

  let detail;
  try {
    detail = await getAdminQuizDetailBySlug(slug);
  } catch (err) {
    return (
      <AdminShell
        title="Quiz Detail"
        subtitle="Edit metadata and manage questions."
        actions={
          <Link
            href="/quiz-bank"
            className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold"
          >
            Back to Quiz Bank
          </Link>
        }
      >
        <PanelCard className="space-y-2">
          <h2 className="font-[family-name:var(--font-anybody)] text-xl font-extrabold uppercase tracking-tight">
            Unable to load quiz
          </h2>
          <p className="text-sm font-medium text-[var(--arena-ink-muted)]">
            {err instanceof Error ? err.message : "Unknown error."}
          </p>
        </PanelCard>
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
      actions={
        <Link
          href="/quiz-bank"
          className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold"
        >
          Back to Quiz Bank
        </Link>
      }
    >
      <div className="space-y-5">
        <PanelCard className="space-y-4">
          <h2 className="font-[family-name:var(--font-anybody)] text-xl font-extrabold uppercase tracking-tight">
            Quiz Metadata
          </h2>
          <QuizEditForm quiz={quiz} />
        </PanelCard>

        <PanelCard className="space-y-4">
          <h2 className="font-[family-name:var(--font-anybody)] text-xl font-extrabold uppercase tracking-tight">
            Questions
          </h2>
          <QuestionManager quizId={quiz.id} quizSlug={quiz.slug} questions={questions} />
        </PanelCard>
      </div>
    </AdminShell>
  );
}
