import { notFound } from "next/navigation";

import { AdminShell } from "@/components/admin-shell";
import { getSessionLiveSnapshot } from "@/lib/session-queries";

import { LiveView } from "./live-view";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = {
  params: Promise<{ id: string }>;
};

export default async function SessionLivePage({ params }: PageProps) {
  const { id } = await params;
  const initial = await getSessionLiveSnapshot(id);

  if (!initial) {
    notFound();
  }

  return (
    <AdminShell
      title={`Live · ${initial.name}`}
      subtitle={`Projector view · join code ${initial.joinCode} · refreshes every 3 seconds.`}
    >
      <LiveView sessionId={id} initial={initial} />
    </AdminShell>
  );
}
