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
    <div className="space-y-4">
      <div className="space-y-2">
        <p className="text-sm font-semibold text-[var(--arena-ink-muted)]">
          {CSV_FORMAT_HINT}
        </p>
        <p className="text-xs text-[var(--arena-ink-muted)]">
          Required: <code>{CSV_REQUIRED_COLUMNS.join(", ")}</code>. Optional:{" "}
          <code>{CSV_OPTIONAL_COLUMNS.join(", ")}</code>.
        </p>
      </div>

      <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-[var(--arena-ink-muted)]">
        <span>CSV File</span>
        <input
          ref={inputRef}
          type="file"
          accept=".csv,text/csv"
          onChange={handleFile}
          aria-label="CSV file to import"
          className="block w-full text-sm font-semibold normal-case tracking-normal"
        />
      </label>

      {fileName ? (
        <p className="text-xs font-semibold text-[var(--arena-ink-muted)]">
          File: {fileName}
        </p>
      ) : null}

      {headerError ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-danger)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-semibold">
          {headerError}
        </p>
      ) : null}

      {parseResult ? (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-3">
            <p className="text-sm font-semibold">
              {drafts.length} valid row{drafts.length === 1 ? "" : "s"} ·{" "}
              {rowErrors.length} error{rowErrors.length === 1 ? "" : "s"}
            </p>
            <button
              type="button"
              onClick={handleImport}
              disabled={isPending || drafts.length === 0}
              className="arena-button bg-[var(--arena-primary)] px-5 py-2 text-sm font-semibold disabled:opacity-60"
            >
              {isPending
                ? "Importing…"
                : `Import ${drafts.length} Question${drafts.length === 1 ? "" : "s"}`}
            </button>
          </div>

          {rowErrors.length > 0 ? (
            <details className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-4 py-3 text-sm">
              <summary className="cursor-pointer font-semibold">
                {rowErrors.length} row(s) will be skipped
              </summary>
              <ul className="mt-2 space-y-1 text-xs">
                {rowErrors.map((err) => (
                  <li key={`${err.rowNumber}-${err.message}`}>
                    Row {err.rowNumber}: {err.message}
                  </li>
                ))}
              </ul>
            </details>
          ) : null}

          {drafts.length > 0 ? (
            <details className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-4 py-3 text-sm">
              <summary className="cursor-pointer font-semibold">
                Preview ({Math.min(drafts.length, 5)} of {drafts.length})
              </summary>
              <ol className="mt-2 space-y-2 text-xs">
                {drafts.slice(0, 5).map((d, idx) => (
                  <li key={idx} className="border-l-2 border-[var(--arena-outline)] pl-2">
                    <p className="font-semibold">{d.prompt}</p>
                    <p className="text-[var(--arena-ink-muted)]">
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
        <p className="rounded-[12px] border-[2px] border-[var(--arena-danger)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-semibold">
          {submitError}
        </p>
      ) : null}

      {summary ? (
        <div className="space-y-2 rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-4 py-3 text-sm">
          <p className="font-semibold">
            Imported {summary.createdCount} question
            {summary.createdCount === 1 ? "" : "s"}.
          </p>
          {summary.failures.length > 0 ? (
            <details>
              <summary className="cursor-pointer font-semibold">
                {summary.failures.length} row(s) failed to insert
              </summary>
              <ul className="mt-2 space-y-1 text-xs">
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
