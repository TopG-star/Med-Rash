/**
 * Client-safe CSV row → CreateQuestionInput validation/transform.
 *
 * Must NOT import server-only modules — this runs in the browser to power
 * the CSV preview UI. The same shape is used by the server action when it
 * commits, so a single contract governs both sides.
 */

import { PILOT_QUESTION_OPTION_COUNT } from "./quiz-bank-types";

export type CsvRowInput = Record<string, unknown>;

export type CsvQuestionDraft = {
  prompt: string;
  options: string[]; // length === PILOT_QUESTION_OPTION_COUNT
  correctIndex: number; // 0-based, 0..PILOT_QUESTION_OPTION_COUNT-1
  explanation: string;
  clinicalArea: string | null;
  tags: string[];
  position: number | null;
  isActive: boolean;
};

export type CsvRowError = {
  rowNumber: number; // 1-based row number from the source CSV (header is row 1)
  message: string;
};

export type CsvParseResult = {
  drafts: CsvQuestionDraft[];
  errors: CsvRowError[];
};

/** Required columns. correct_index is 1-based in the CSV for human friendliness. */
export const CSV_REQUIRED_COLUMNS = [
  "prompt",
  "option_1",
  "option_2",
  "option_3",
  "option_4",
  "correct_index",
  "explanation",
] as const;

/** Optional columns. */
export const CSV_OPTIONAL_COLUMNS = [
  "clinical_area",
  "tags",
  "position",
  "is_active",
] as const;

const TAG_SEPARATOR = "|";

function normalizeHeader(h: string): string {
  return h.trim().toLowerCase().replace(/\s+/g, "_");
}

/** Lowercase + trim header keys on every row to make lookups deterministic. */
function normalizeRow(row: CsvRowInput): CsvRowInput {
  const out: CsvRowInput = {};
  for (const [k, v] of Object.entries(row)) {
    out[normalizeHeader(k)] = v;
  }
  return out;
}

function cellString(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value).trim();
}

function cellOptionalString(value: unknown): string | null {
  const s = cellString(value);
  return s.length === 0 ? null : s;
}

function cellInteger(value: unknown): number | null {
  const s = cellString(value);
  if (s.length === 0) return null;
  const n = Number(s);
  if (!Number.isInteger(n)) return null;
  return n;
}

function cellBoolean(value: unknown, fallback: boolean): boolean {
  const s = cellString(value).toLowerCase();
  if (s.length === 0) return fallback;
  if (["true", "1", "yes", "y", "active"].includes(s)) return true;
  if (["false", "0", "no", "n", "inactive"].includes(s)) return false;
  return fallback;
}

function cellTags(value: unknown): string[] {
  const s = cellString(value);
  if (s.length === 0) return [];
  return s
    .split(TAG_SEPARATOR)
    .map((t) => t.trim().toLowerCase())
    .filter((t) => t.length > 0);
}

/**
 * Validate the supplied header list. Returns an error message if any
 * required column is missing, otherwise null.
 */
export function validateCsvHeaders(headers: string[]): string | null {
  const normalized = new Set(headers.map(normalizeHeader));
  const missing = CSV_REQUIRED_COLUMNS.filter((c) => !normalized.has(c));
  if (missing.length > 0) {
    return `Missing required column(s): ${missing.join(", ")}.`;
  }
  return null;
}

/**
 * Parse + validate an array of CSV row objects (already parsed by papaparse
 * with `header: true`). Returns a discriminated result: drafts that passed
 * full validation alongside per-row error messages.
 *
 * `startingRowNumber` is the 1-based source-row number of the FIRST data row
 * (typically 2, because row 1 is the header).
 */
export function parseCsvQuestionRows(
  rows: CsvRowInput[],
  startingRowNumber = 2,
): CsvParseResult {
  const drafts: CsvQuestionDraft[] = [];
  const errors: CsvRowError[] = [];

  rows.forEach((rawRow, idx) => {
    const rowNumber = startingRowNumber + idx;
    const row = normalizeRow(rawRow);

    // Skip entirely blank rows.
    const hasAnyValue = Object.values(row).some(
      (v) => cellString(v).length > 0,
    );
    if (!hasAnyValue) return;

    const prompt = cellString(row.prompt);
    if (prompt.length === 0) {
      errors.push({ rowNumber, message: "prompt is required." });
      return;
    }
    if (prompt.length > 1200) {
      errors.push({ rowNumber, message: "prompt exceeds 1200 characters." });
      return;
    }

    const options: string[] = [];
    let optionError: string | null = null;
    for (let i = 1; i <= PILOT_QUESTION_OPTION_COUNT; i += 1) {
      const opt = cellString(row[`option_${i}`]);
      if (opt.length === 0) {
        optionError = `option_${i} is required.`;
        break;
      }
      if (opt.length > 400) {
        optionError = `option_${i} exceeds 400 characters.`;
        break;
      }
      options.push(opt);
    }
    if (optionError) {
      errors.push({ rowNumber, message: optionError });
      return;
    }
    const uniqueOptions = new Set(options.map((o) => o.toLowerCase()));
    if (uniqueOptions.size !== options.length) {
      errors.push({
        rowNumber,
        message: "options must be unique (case-insensitive).",
      });
      return;
    }

    const correctRaw = cellInteger(row.correct_index);
    if (correctRaw === null) {
      errors.push({ rowNumber, message: "correct_index must be an integer." });
      return;
    }
    if (correctRaw < 1 || correctRaw > PILOT_QUESTION_OPTION_COUNT) {
      errors.push({
        rowNumber,
        message: `correct_index must be between 1 and ${PILOT_QUESTION_OPTION_COUNT}.`,
      });
      return;
    }
    const correctIndex = correctRaw - 1;

    const explanation = cellString(row.explanation);
    if (explanation.length === 0) {
      errors.push({ rowNumber, message: "explanation is required." });
      return;
    }
    if (explanation.length > 1200) {
      errors.push({
        rowNumber,
        message: "explanation exceeds 1200 characters.",
      });
      return;
    }

    const clinicalAreaRaw = cellOptionalString(row.clinical_area);
    if (clinicalAreaRaw && clinicalAreaRaw.length > 120) {
      errors.push({
        rowNumber,
        message: "clinical_area exceeds 120 characters.",
      });
      return;
    }

    const tagsRaw = cellTags(row.tags);
    const tagsClean: string[] = [];
    let tagError: string | null = null;
    for (const t of tagsRaw) {
      if (t.length > 48) {
        tagError = `tag '${t}' exceeds 48 characters.`;
        break;
      }
      if (!tagsClean.includes(t)) tagsClean.push(t);
    }
    if (tagError) {
      errors.push({ rowNumber, message: tagError });
      return;
    }

    let position: number | null = null;
    if (cellString(row.position).length > 0) {
      const p = cellInteger(row.position);
      if (p === null || p < 0 || p > 9999) {
        errors.push({
          rowNumber,
          message: "position must be an integer between 0 and 9999.",
        });
        return;
      }
      position = p;
    }

    const isActive = cellBoolean(row.is_active, true);

    drafts.push({
      prompt,
      options,
      correctIndex,
      explanation,
      clinicalArea: clinicalAreaRaw,
      tags: tagsClean,
      position,
      isActive,
    });
  });

  return { drafts, errors };
}

/**
 * Hint string for the UI describing the expected CSV shape.
 */
export const CSV_FORMAT_HINT = [
  `Required columns: ${CSV_REQUIRED_COLUMNS.join(", ")}.`,
  `Optional columns: ${CSV_OPTIONAL_COLUMNS.join(", ")}.`,
  `correct_index is 1-based (1..${PILOT_QUESTION_OPTION_COUNT}).`,
  `tags within a cell are pipe-separated, e.g. "guideline|product".`,
].join(" ");
