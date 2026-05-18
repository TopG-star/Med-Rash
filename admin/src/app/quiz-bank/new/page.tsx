import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";

import { QuizCreateForm } from "./quiz-create-form";

export const dynamic = "force-dynamic";

export default function NewQuizPage() {
  return (
    <AdminShell
      title="Create Quiz"
      subtitle="Define a new quiz container. Questions are added on the next screen."
      actions={
        <Link
          href="/quiz-bank"
          className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold"
        >
          Back to Quiz Bank
        </Link>
      }
    >
      <PanelCard className="space-y-4">
        <QuizCreateForm />
      </PanelCard>
    </AdminShell>
  );
}
