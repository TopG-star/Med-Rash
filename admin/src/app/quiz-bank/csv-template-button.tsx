"use client";

import { CSV_TEMPLATE_FILENAME, buildCsvTemplate } from "@/lib/quiz-csv";

type Props = {
  /** Visual variant — primary action vs. inline ghost link. */
  variant?: "primary" | "ghost";
  /** Optional className override (e.g. to fit a row layout). */
  className?: string;
  /** Override the visible label (default: "Download CSV template"). */
  label?: string;
};

/**
 * Renders a button that builds the canonical quiz-import CSV template in the
 * browser and triggers a download. No network round-trip; the template is
 * generated from the same column constants the parser validates against, so
 * the file is guaranteed to round-trip cleanly through the import panel.
 */
export function CsvTemplateButton({
  variant = "ghost",
  className,
  label = "Download CSV template",
}: Props) {
  function handleDownload() {
    const csv = buildCsvTemplate();
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = CSV_TEMPLATE_FILENAME;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    // Defer revoke so Safari/Firefox can finalize the download.
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  const base =
    variant === "primary"
      ? "vp-button vp-button-secondary"
      : "vp-link-ghost";
  return (
    <button
      type="button"
      onClick={handleDownload}
      className={className ? `${base} ${className}` : base}
    >
      {label}
    </button>
  );
}
