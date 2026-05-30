import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";

import { QuizCreateForm } from "./quiz-create-form";

export const dynamic = "force-dynamic";

type SearchParams = { bulk?: string };

export default async function NewQuizPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const session = await requireAdminSession({
    currentPath: "/quiz-bank/new",
  });
  const sp = await searchParams;
  const bulkMode = sp.bulk === "1";
  return (
    <AdminShell
      title={bulkMode ? "Create Quiz · Bulk CSV Import" : "Create Quiz"}
      subtitle={
        bulkMode
          ? "Fill the quiz metadata and attach a CSV of questions. Both land in one step."
          : "Define a new quiz container. Questions are added on the next screen."
      }
      titleSize="sm"
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
          <QuizCreateForm bulkMode={bulkMode} />
        </div>
      </div>
    </AdminShell>
  );
}
