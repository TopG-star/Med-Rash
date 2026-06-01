import { describe, expect, it } from "vitest";

import {
  buildCsvFromQuestions,
  csvExportFilename,
  parseCsvQuestionRows,
  validateCsvHeaders,
} from "./quiz-csv";
import type { QuestionRecord } from "./quiz-bank-types";

function makeQuestion(overrides: Partial<QuestionRecord> = {}): QuestionRecord {
  return {
    id: "q-1",
    quizId: "quiz-1",
    prompt: "What is 2 + 2?",
    options: ["3", "4", "5", "6"],
    correctIndex: 1,
    explanation: "Basic arithmetic.",
    clinicalArea: "Pharmacology",
    tags: ["math", "basics"],
    position: 1,
    isActive: true,
    createdAt: "2025-01-01T00:00:00.000Z",
    ...overrides,
  };
}

// Minimal CSV row splitter that handles quoted cells with embedded commas,
// quotes, and newlines — sufficient for round-trip tests against our own
// emitter. Mirrors what papaparse does at runtime.
function parseCsvText(csv: string): Record<string, string>[] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let inQuotes = false;
  for (let i = 0; i < csv.length; i += 1) {
    const ch = csv[i];
    if (inQuotes) {
      if (ch === '"') {
        if (csv[i + 1] === '"') {
          cell += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        cell += ch;
      }
      continue;
    }
    if (ch === '"') {
      inQuotes = true;
      continue;
    }
    if (ch === ",") {
      row.push(cell);
      cell = "";
      continue;
    }
    if (ch === "\n") {
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
      continue;
    }
    if (ch === "\r") continue;
    cell += ch;
  }
  if (cell.length > 0 || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }
  const [header, ...data] = rows;
  return data
    .filter((r) => r.some((c) => c.length > 0))
    .map((r) => {
      const obj: Record<string, string> = {};
      header.forEach((h, idx) => {
        obj[h] = r[idx] ?? "";
      });
      return obj;
    });
}

describe("buildCsvFromQuestions", () => {
  it("emits required + optional columns in canonical order", () => {
    const csv = buildCsvFromQuestions([makeQuestion()]);
    const headerLine = csv.split("\n")[0];
    expect(headerLine).toBe(
      "prompt,option_1,option_2,option_3,option_4,correct_index,explanation,clinical_area,tags,position,is_active",
    );
  });

  it("emits correct_index 1-based and is_active as true/false", () => {
    const csv = buildCsvFromQuestions([
      makeQuestion({ correctIndex: 0, isActive: true }),
      makeQuestion({ id: "q-2", correctIndex: 3, isActive: false }),
    ]);
    const rows = parseCsvText(csv);
    expect(rows[0].correct_index).toBe("1");
    expect(rows[0].is_active).toBe("true");
    expect(rows[1].correct_index).toBe("4");
    expect(rows[1].is_active).toBe("false");
  });

  it("renders empty clinical_area cell when null and joins tags with |", () => {
    const csv = buildCsvFromQuestions([
      makeQuestion({ clinicalArea: null, tags: ["a", "b", "c"] }),
    ]);
    const rows = parseCsvText(csv);
    expect(rows[0].clinical_area).toBe("");
    expect(rows[0].tags).toBe("a|b|c");
  });

  it("escapes commas, quotes, and newlines in cells", () => {
    const csv = buildCsvFromQuestions([
      makeQuestion({
        prompt: 'Pick "one", or two\nshould wrap',
        options: ["a", "b", "c", "d"],
      }),
    ]);
    const rows = parseCsvText(csv);
    expect(rows[0].prompt).toBe('Pick "one", or two\nshould wrap');
  });

  it("round-trips cleanly through the import parser", () => {
    const originals: QuestionRecord[] = [
      makeQuestion(),
      makeQuestion({
        id: "q-2",
        prompt: "Which is teratogenic in pregnancy?",
        options: ["Apixaban", "Warfarin", "LMWH", "UFH"],
        correctIndex: 1,
        explanation: "Warfarin crosses the placenta.",
        clinicalArea: null,
        tags: [],
        position: 2,
        isActive: false,
      }),
    ];
    const csv = buildCsvFromQuestions(originals);
    const rows = parseCsvText(csv);

    const headers = csv.split("\n")[0].split(",");
    expect(validateCsvHeaders(headers)).toBeNull();

    const { drafts, errors } = parseCsvQuestionRows(rows);
    expect(errors).toEqual([]);
    expect(drafts).toHaveLength(originals.length);
    drafts.forEach((d, i) => {
      const o = originals[i];
      expect(d.prompt).toBe(o.prompt);
      expect(d.options).toEqual(o.options);
      expect(d.correctIndex).toBe(o.correctIndex);
      expect(d.explanation).toBe(o.explanation);
      expect(d.clinicalArea).toBe(o.clinicalArea);
      expect(d.tags).toEqual(o.tags);
      expect(d.position).toBe(o.position);
      expect(d.isActive).toBe(o.isActive);
    });
  });
});

describe("csvExportFilename", () => {
  it("uses the slug verbatim when slug-safe", () => {
    expect(csvExportFilename("cap-antibiotics")).toBe("cap-antibiotics-questions.csv");
  });

  it("sanitizes unsafe characters", () => {
    expect(csvExportFilename("Cardio/Renal 2026!")).toBe("cardio-renal-2026-questions.csv");
  });

  it("falls back when slug is empty after sanitization", () => {
    expect(csvExportFilename("///")).toBe("quiz-questions.csv");
  });
});
