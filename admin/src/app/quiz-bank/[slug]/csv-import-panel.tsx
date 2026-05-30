"use client";

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

import { importQuestionsAction } from "../actions";
import { CsvTemplateButton } from "../csv-template-button";

type Props = {
  quizId: string;
  quizSlug: string;
};

type ImportSummary = {
  createdCount: number;
  failures: Array<{ index: number; message: string }>;
};

export function CsvImportPanel({ quizId, quizSlug }: Props) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [parseResult, setParseResult] = useState<CsvParseResult | null>(null);
  const [headerError, setHeaderError] = useState<string | null>(null);
  const [summary, setSummary] = useState<ImportSummary | null>(null);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function resetState() {
    setParseResult(null);
    setHeaderError(null);
    setSummary(null);
    setSubmitError(null);
  }

  async function handleFile(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    resetState();
    setFileName(file?.name ?? null);
    if (!file) return;

    // Dynamic import keeps papaparse out of the initial route bundle.
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

  function handleImport() {
    if (!parseResult || parseResult.drafts.length === 0) return;
    setSubmitError(null);
    setSummary(null);
    startTransition(async () => {
      const result = await importQuestionsAction(quizId, quizSlug, parseResult.drafts);
      if (!result.ok) {
        setSubmitError(result.message);
        return;
      }
      setSummary({
        createdCount: result.data.created.length,
        failures: result.data.failures,
      });
      if (inputRef.current) inputRef.current.value = "";
      setFileName(null);
      setParseResult(null);
    });
  }

  const drafts = parseResult?.drafts ?? [];
  const rowErrors = parseResult?.errors ?? [];

  return (
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
          ref={inputRef}
          type="file"
          accept=".csv,text/csv"
          onChange={handleFile}
          aria-label="CSV file to import"
          className="vp-file-input"
        />
      </label>

      {fileName ? (
        <p className="vp-q-meta">File: {fileName}</p>
      ) : null}

      {headerError ? (
        <p className="vp-banner vp-banner-error">{headerError}</p>
      ) : null}

      {parseResult ? (
        <div className="vp-vstack">
          <div className="vp-row-tight">
            <p className="vp-q-meta vp-row-label-strong">
              {drafts.length} valid row{drafts.length === 1 ? "" : "s"} ·{" "}
              {rowErrors.length} error{rowErrors.length === 1 ? "" : "s"}
            </p>
            <button
              type="button"
              onClick={handleImport}
              disabled={isPending || drafts.length === 0}
              className="vp-button vp-button-primary vp-button-sm"
            >
              {isPending
                ? "Importing…"
                : `Import ${drafts.length} Question${drafts.length === 1 ? "" : "s"}`}
            </button>
          </div>

          {rowErrors.length > 0 ? (
            <details className="vp-details">
              <summary>
                {rowErrors.length} row(s) will be skipped
              </summary>
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
                    <p className="vp-preview-prompt">
                      {d.prompt}
                    </p>
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

      {submitError ? (
        <p className="vp-banner vp-banner-error">{submitError}</p>
      ) : null}

      {summary ? (
        <div className="vp-summary-banner">
          <p>
            Imported {summary.createdCount} question
            {summary.createdCount === 1 ? "" : "s"}.
          </p>
          {summary.failures.length > 0 ? (
            <details className="vp-details vp-mt-3">
              <summary>
                {summary.failures.length} row(s) failed to insert
              </summary>
              <ul>
                {summary.failures.map((f) => (
                  <li key={`${f.index}-${f.message}`}>
                    Draft #{f.index + 1}: {f.message}
                  </li>
                ))}
              </ul>
            </details>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
