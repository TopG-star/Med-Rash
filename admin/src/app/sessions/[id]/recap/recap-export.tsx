"use client";

import { useState } from "react";

import { csvFilenameSegment, serializeCsv } from "@/lib/csv-export";
import type { SessionLiveTopRow } from "@/lib/session-queries";

type RecapExportProps = {
  sessionName: string;
  joinCode: string;
  standings: SessionLiveTopRow[];
};

export function RecapExport({
  sessionName,
  joinCode,
  standings,
}: RecapExportProps) {
  const [busy, setBusy] = useState(false);

  function handleDownload() {
    if (standings.length === 0 || busy) return;
    setBusy(true);
    try {
      const csv = serializeCsv(
        standings.map((row, index) => ({
          rank: index + 1,
          displayName: row.displayName,
          facility: row.facility ?? "",
          score: row.score,
          totalQuestions: row.totalQuestions,
          percent:
            row.totalQuestions > 0
              ? Math.round((row.score / row.totalQuestions) * 100)
              : 0,
          completedAt: row.completedAt,
          participantId: row.participantId,
        })),
        [
          { header: "Rank", select: (r) => r.rank },
          { header: "Display Name", select: (r) => r.displayName },
          { header: "Facility", select: (r) => r.facility },
          { header: "Score", select: (r) => r.score },
          { header: "Total Questions", select: (r) => r.totalQuestions },
          { header: "Percent", select: (r) => r.percent },
          { header: "Completed At", select: (r) => r.completedAt },
          { header: "Participant ID", select: (r) => r.participantId },
        ],
      );
      const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
      const url = URL.createObjectURL(blob);
      const safeName = csvFilenameSegment(sessionName) || "session";
      const safeCode = csvFilenameSegment(joinCode) || "code";
      const filename = `medrash-recap-${safeName}-${safeCode}.csv`;
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = filename;
      document.body.appendChild(anchor);
      anchor.click();
      document.body.removeChild(anchor);
      URL.revokeObjectURL(url);
    } finally {
      setBusy(false);
    }
  }

  const disabled = standings.length === 0 || busy;

  return (
    <button
      type="button"
      onClick={handleDownload}
      disabled={disabled}
      className="arena-button bg-[#FFDE59] px-4 py-2 text-sm font-extrabold uppercase tracking-[0.05em] text-[#1b1b1b] disabled:cursor-not-allowed disabled:opacity-40"
      aria-label="Export standings as CSV"
    >
      {busy ? "Exporting…" : "Export CSV"}
    </button>
  );
}
