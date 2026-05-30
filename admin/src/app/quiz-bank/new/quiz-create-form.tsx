"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useTransition } from "react";
import type { ChangeEvent } from "react";

import {
  CSV_FORMAT_HINT,
  CSV_OPTIONAL_COLUMNS,
  CSV_REQUIRED_COLUMNS,
  parseCsvQuestionRows,
  validateCsvHeaders,
  type CsvParseResult,
  type CsvRowInput,
} from "@/lib/quiz-csv";

import { createQuizAction, createQuizWithBulkAction } from "../actions";
import { CsvTemplateButton } from "../csv-template-button";

type Props = {
  /** When true, render the combined "metadata + CSV import" variant. */
  bulkMode?: boolean;
};

function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
}

export function QuizCreateForm({ bulkMode = false }: Props) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [slug, setSlug] = useState("");
  const [slugTouched, setSlugTouched] = useState(false);

  // --- bulk-mode CSV state -------------------------------------------------
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [headerError, setHeaderError] = useState<string | null>(null);
  const [parseResult, setParseResult] = useState<CsvParseResult | null>(null);

  function resetCsvState() {
    setHeaderError(null);
    setParseResult(null);
  }

  async function handleFile(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    resetCsvState();
    setFileName(file?.name ?? null);
    if (!file) return;
    const Papa = (await import("papaparse")).default;
    Papa.parse<CsvRowInput>(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const headers = results.meta.fields ?? [];
        const headerErr = validateCsvHeaders(headers);
        if (headerErr) {
          setHeaderError(headerErr);
          setParseResult(null);
          return;
        }
        const parsed = parseCsvQuestionRows(results.data ?? []);
        setParseResult(parsed);
      },
      error: (err) => {
        setHeaderError(`CSV parse failed: ${err.message}`);
        setParseResult(null);
      },
    });
  }

  function handleTitleChange(e: React.ChangeEvent<HTMLInputElement>) {
    if (!slugTouched) setSlug(slugify(e.target.value));
  }

  function handleSubmit(formData: FormData) {
    setError(null);
    const payload = {
      slug: String(formData.get("slug") ?? "").trim(),
      title: String(formData.get("title") ?? "").trim(),
      category: String(formData.get("category") ?? "").trim(),
      product: String(formData.get("product") ?? "").trim() || null,
      summary: String(formData.get("summary") ?? "").trim(),
      questionCountDefault: Number(formData.get("questionCountDefault") ?? 10),
      isActive: formData.get("isActive") === "on",
    };

    if (bulkMode) {
      const drafts = parseResult?.drafts ?? [];
      if (drafts.length === 0) {
        setError(
          headerError ??
            "Attach a CSV with at least one valid row, or switch to the standard create flow.",
        );
        return;
      }
      startTransition(async () => {
        const result = await createQuizWithBulkAction(payload, drafts);
        if (!result.ok) {
          setError(result.message);
          return;
        }
        const { quiz, imported, failed } = result.data;
        const params = new URLSearchParams({
          focus: "questions",
          imported: String(imported),
        });
        if (failed > 0) params.set("failed", String(failed));
        router.push(`/quiz-bank/${quiz.slug}?${params.toString()}#questions`);
      });
      return;
    }

    startTransition(async () => {
      const result = await createQuizAction(payload);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      // H2: hand the admin straight to the Questions section of the new
      // quiz instead of leaving them on the metadata-only screen.
      router.push(`/quiz-bank/${result.data.slug}?focus=questions#questions`);
    });
  }

  const drafts = parseResult?.drafts ?? [];
  const rowErrors = parseResult?.errors ?? [];

  return (
    <form action={handleSubmit} className="vp-vstack vp-vstack-lg">
      <div className="vp-form-grid cols-2">
        <label className="vp-field col-span-2">
          <span className="vp-label">Title</span>
          <input
            name="title"
            required
            maxLength={160}
            onChange={handleTitleChange}
            className="vp-input"
            placeholder="Clexane Indications Refresher"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Slug</span>
          <input
            name="slug"
            required
            maxLength={64}
            value={slug}
            onChange={(e) => {
              setSlug(slugify(e.target.value));
              setSlugTouched(true);
            }}
            className="vp-input"
            placeholder="clexane-indications"
            pattern="[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?"
            title="lowercase alphanumeric with optional dashes"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Category</span>
          <input
            name="category"
            required
            maxLength={80}
            className="vp-input"
            placeholder="Anticoagulation"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Product (optional)</span>
          <input
            name="product"
            maxLength={80}
            className="vp-input"
            placeholder="Clexane"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Default Question Count</span>
          <input
            name="questionCountDefault"
            type="number"
            min={1}
            max={50}
            defaultValue={10}
            required
            className="vp-input"
          />
        </label>
        <label className="vp-field col-span-2">
          <span className="vp-label">Summary</span>
          <textarea
            name="summary"
            required
            maxLength={600}
            rows={3}
            className="vp-textarea"
            placeholder="Short description shown to participants."
          />
        </label>
        <label className="vp-checkbox-row col-span-2">
          <input type="checkbox" name="isActive" defaultChecked /> Active
        </label>
      </div>

      {bulkMode ? (
        <section className="vp-panel">
          <div className="vp-panel-head">
            <h3 className="vp-panel-title">CSV Bulk Import</h3>
          </div>
          <div className="vp-vstack vp-vstack-md">
            <div className="vp-vstack vp-vstack-sm">
              <p className="vp-csv-hint">{CSV_FORMAT_HINT}</p>
              <p className="vp-csv-hint vp-csv-hint-tight">
                Required: <code>{CSV_REQUIRED_COLUMNS.join(", ")}</code>. Optional:{" "}
                <code>{CSV_OPTIONAL_COLUMNS.join(", ")}</code>.
              </p>
              <div>
                <CsvTemplateButton />
              </div>
            </div>

            <label className="vp-field">
              <span className="vp-label">CSV File</span>
              <input
                ref={fileInputRef}
                type="file"
                accept=".csv,text/csv"
                onChange={handleFile}
                aria-label="CSV file to import"
                className="vp-file-input"
              />
            </label>

            {fileName ? <p className="vp-q-meta">File: {fileName}</p> : null}

            {headerError ? (
              <p className="vp-banner vp-banner-error">{headerError}</p>
            ) : null}

            {parseResult ? (
              <div className="vp-vstack">
                <p className="vp-q-meta vp-row-label-strong">
                  {drafts.length} valid row{drafts.length === 1 ? "" : "s"} ·{" "}
                  {rowErrors.length} error{rowErrors.length === 1 ? "" : "s"}
                </p>
                {rowErrors.length > 0 ? (
                  <details className="vp-details">
                    <summary>{rowErrors.length} row(s) will be skipped</summary>
                    <ul>
                      {rowErrors.map((err) => (
                        <li key={`${err.rowNumber}-${err.message}`}>
                          Row {err.rowNumber}: {err.message}
                        </li>
                      ))}
                    </ul>
                  </details>
                ) : null}
                {drafts.length > 0 ? (
                  <details className="vp-details">
                    <summary>
                      Preview ({Math.min(drafts.length, 5)} of {drafts.length})
                    </summary>
                    <ol className="vp-list-bare">
                      {drafts.slice(0, 5).map((d, idx) => (
                        <li key={idx} className="vp-preview-row">
                          <p className="vp-preview-prompt">{d.prompt}</p>
                          <p className="vp-preview-meta">
                            Correct: {d.options[d.correctIndex]} · tags:{" "}
                            {d.tags.length > 0 ? d.tags.join(", ") : "—"}
                          </p>
                        </li>
                      ))}
                    </ol>
                  </details>
                ) : null}
              </div>
            ) : null}
          </div>
        </section>
      ) : null}

      {error ? <p className="vp-banner vp-banner-error">{error}</p> : null}

      <div className="vp-button-row">
        <button
          type="submit"
          disabled={isPending || (bulkMode && drafts.length === 0)}
          className="vp-button vp-button-primary"
        >
          {isPending
            ? bulkMode
              ? "Creating & Importing…"
              : "Creating…"
            : bulkMode
              ? `Create Quiz & Import ${drafts.length} Question${drafts.length === 1 ? "" : "s"}`
              : "Create Quiz"}
        </button>
      </div>
    </form>
  );
}
