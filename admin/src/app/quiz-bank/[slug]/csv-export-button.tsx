"use client";

import {
  buildCsvFromQuestions,
  csvExportFilename,
} from "@/lib/quiz-csv";
import type { QuestionRecord } from "@/lib/quiz-bank-types";

type Props = {
  quizSlug: string;
  questions: readonly QuestionRecord[];
  /** Visual variant — primary action vs. inline ghost link. */
  variant?: "primary" | "ghost";
  /** Optional className override (e.g. to fit a row layout). */
  className?: string;
  /** Override the visible label (default: "Export questions to CSV"). */
  label?: string;
};

/**
 * Builds a CSV of every question on the quiz in the canonical import shape
 * and triggers a browser download. Output round-trips cleanly through the
 * Bulk Import panel, so admins can edit questions offline and re-upload
 * without column reshuffling. No network round-trip.
 */
export function CsvExportButton({
  quizSlug,
  questions,
  variant = "ghost",
  className,
  label = "Export questions to CSV",
}: Props) {
  const disabled = questions.length === 0;

  function handleExport() {
    if (disabled) return;
    const csv = buildCsvFromQuestions(questions);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = csvExportFilename(quizSlug);
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    // Defer revoke so Safari/Firefox can finalize the download.
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  const base =
    variant === "primary" ? "vp-button vp-button-secondary" : "vp-link-ghost";
  const composed = className ? `${base} ${className}` : base;
  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={disabled}
      title={
        disabled
          ? "Add at least one question before exporting."
          : "Download every question as a CSV that re-imports cleanly."
      }
      className={composed}
    >
      {label}
    </button>
  );
}
