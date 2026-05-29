import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";

import { QuizCreateForm } from "./quiz-create-form";

export const dynamic = "force-dynamic";

export default async function NewQuizPage() {
  const session = await requireAdminSession({
    currentPath: "/quiz-bank/new",
  });
  return (
    <AdminShell
      title="Create Quiz"
      subtitle="Define a new quiz container. Questions are added on the next screen."
      user={{ email: session.email, role: session.role }}
      actions={
        <span className="vp-scope">
          <Link href="/quiz-bank" className="vp-button vp-button-secondary">
            Back to Quiz Bank
          </Link>
        </span>
      }
    >
      <div className="vp-scope">
        <div className="vp-card">
          <QuizCreateForm />
        </div>
      </div>
    </AdminShell>
  );
}
