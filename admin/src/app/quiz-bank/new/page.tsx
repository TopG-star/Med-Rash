import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";
import { requireOwner } from "@/lib/admin-session";

import { QuizCreateForm } from "./quiz-create-form";

export const dynamic = "force-dynamic";

export default async function NewQuizPage() {
  const session = await requireOwner({
    currentPath: "/quiz-bank/new",
  });
  return (
    <AdminShell
      title="Create Quiz"
      subtitle="Define a new quiz container. Questions are added on the next screen."
      user={{ email: session.email, role: session.role }}
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
