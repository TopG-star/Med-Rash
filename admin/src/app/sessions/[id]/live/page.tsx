import { notFound } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";
import { getSessionLiveSnapshot } from "@/lib/session-queries";

import { LiveView } from "./live-view";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = {
  params: Promise<{ id: string }>;
};

export default async function SessionLivePage({ params }: PageProps) {
  const { id } = await params;
  const session = await requireAdminSession({
    currentPath: `/sessions/${id}/live`,
  });
  const initial = await getSessionLiveSnapshot(id);

  if (!initial) {
    notFound();
  }

  return (
    <AdminShell
      title={`Host Control Room · ${initial.name}`}
      subtitle={`Live distribution + audience · join code ${initial.joinCode} · refreshes every 3 seconds.`}
      user={{ email: session.email, role: session.role }}
    >
      <LiveView sessionId={id} initial={initial} />
    </AdminShell>
  );
}
