/**
 * Tiny RFC 4180 CSV serializer.
 *
 * Pure / client-safe — no `server-only` deps. The Reports surface uses this
 * both server-side (in route handlers) and could reuse it client-side later
 * for a "download visible table" affordance without re-bundling logic.
 *
 * Rules implemented:
 *   - Comma-separated values, CRLF row terminator.
 *   - Cells containing comma, quote, CR or LF are wrapped in double quotes.
 *   - Embedded double quotes are escaped by doubling them ("" inside "...").
 *   - null / undefined render as empty.
 *   - arrays render as pipe-joined values (matches CSV import convention).
 *   - Date instances render as ISO 8601.
 *   - Objects fall back to JSON.stringify (last resort for jsonb columns).
 */

export type CsvCellValue =
  | string
  | number
  | boolean
  | bigint
  | Date
  | null
  | undefined
  | readonly CsvCellValue[]
  | { toString(): string };

export type CsvColumn<TRow> = {
  header: string;
  select: (row: TRow) => CsvCellValue;
};

const CSV_NEEDS_QUOTING = /[",\r\n]/;

function renderCell(value: CsvCellValue): string {
  if (value === null || value === undefined) return "";
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) {
    return value.map((v) => renderCell(v)).join("|");
  }
  if (typeof value === "object") {
    try {
      return JSON.stringify(value);
    } catch {
      return String(value);
    }
  }
  return String(value);
}

function escapeCell(raw: string): string {
  if (!CSV_NEEDS_QUOTING.test(raw)) return raw;
  return `"${raw.replace(/"/g, '""')}"`;
}

/**
 * Serialize a row collection to a CSV string. Header row is always emitted
 * (even if `rows` is empty) so importers can still read the schema.
 */
export function serializeCsv<TRow>(
  rows: readonly TRow[],
  columns: readonly CsvColumn<TRow>[],
): string {
  const lines: string[] = [];
  lines.push(columns.map((c) => escapeCell(c.header)).join(","));
  for (const row of rows) {
    lines.push(
      columns.map((c) => escapeCell(renderCell(c.select(row)))).join(","),
    );
  }
  return lines.join("\r\n");
}

/**
 * P0.7 — single-row serialiser used by the streaming export. Renders one
 * row WITHOUT a trailing newline so the caller controls separators.
 */
export function serializeCsvRow<TRow>(
  row: TRow,
  columns: readonly CsvColumn<TRow>[],
): string {
  return columns.map((c) => escapeCell(renderCell(c.select(row)))).join(",");
}

/**
 * P0.7 — header line for streaming exports. Excludes the trailing CRLF so
 * the caller appends `\r\n` (or nothing if no rows follow yet).
 */
export function serializeCsvHeader<TRow>(
  columns: readonly CsvColumn<TRow>[],
): string {
  return columns.map((c) => escapeCell(c.header)).join(",");
}

/**
 * P0.7 — wrap a row collection in a ReadableStream of UTF-8 bytes prefixed
 * with the BOM (so Excel opens the file in the right encoding). The header
 * row is always emitted, even when `rows` is empty.
 *
 * Streaming response avoids buffering the entire CSV in memory before the
 * Response object materialises — important for large /reports exports
 * (50k attempts × 26 columns can exceed Netlify's 6 MB response limit when
 * buffered).
 */
export function streamCsv<TRow>(
  rows: Iterable<TRow> | AsyncIterable<TRow>,
  columns: readonly CsvColumn<TRow>[],
): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        // BOM + header line.
        controller.enqueue(encoder.encode("\uFEFF"));
        controller.enqueue(encoder.encode(serializeCsvHeader(columns)));

        const iterable = rows as AsyncIterable<TRow> & Iterable<TRow>;
        const isAsync =
          typeof (iterable as AsyncIterable<TRow>)[Symbol.asyncIterator] ===
          "function";
        if (isAsync) {
          for await (const row of iterable as AsyncIterable<TRow>) {
            controller.enqueue(
              encoder.encode("\r\n" + serializeCsvRow(row, columns)),
            );
          }
        } else {
          for (const row of iterable as Iterable<TRow>) {
            controller.enqueue(
              encoder.encode("\r\n" + serializeCsvRow(row, columns)),
            );
          }
        }
        controller.close();
      } catch (err) {
        controller.error(err);
      }
    },
  });
}

/**
 * Sanitize a filename segment to safe ASCII for `Content-Disposition`.
 * Defensive — keeps Latin letters/digits/dash/underscore/dot only.
 */
export function csvFilenameSegment(input: string): string {
  return input
    .replace(/[^a-zA-Z0-9_.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80) || "export";
}
