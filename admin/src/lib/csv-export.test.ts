import { describe, expect, it } from "vitest";

import {
  csvFilenameSegment,
  serializeCsv,
  serializeCsvHeader,
  serializeCsvRow,
  streamCsv,
  type CsvColumn,
} from "./csv-export";

type Row = { id: string; label: string; n: number | null };

const COLUMNS: ReadonlyArray<CsvColumn<Row>> = [
  { header: "id", select: (r) => r.id },
  { header: "label", select: (r) => r.label },
  { header: "n", select: (r) => r.n },
];

async function readStream(stream: ReadableStream<Uint8Array>): Promise<string> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value) chunks.push(value);
  }
  const total = chunks.reduce((acc, c) => acc + c.length, 0);
  const merged = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    merged.set(c, offset);
    offset += c.length;
  }
  return new TextDecoder("utf-8", { ignoreBOM: true }).decode(merged);
}

describe("serializeCsv (buffered)", () => {
  it("emits header even when rows are empty", () => {
    expect(serializeCsv([], COLUMNS)).toBe("id,label,n");
  });

  it("quotes cells with comma / quote / newline", () => {
    const out = serializeCsv(
      [{ id: "1", label: 'has "quote", and , comma', n: null }],
      COLUMNS,
    );
    expect(out).toBe('id,label,n\r\n1,"has ""quote"", and , comma",');
  });
});

describe("serializeCsvHeader / serializeCsvRow", () => {
  it("matches the buffered serializer cell-for-cell", () => {
    const row: Row = { id: "x", label: "alpha", n: 7 };
    const buffered = serializeCsv([row], COLUMNS);
    const split = `${serializeCsvHeader(COLUMNS)}\r\n${serializeCsvRow(row, COLUMNS)}`;
    expect(buffered).toBe(split);
  });
});

describe("streamCsv", () => {
  it("emits BOM + header + rows in CRLF format", async () => {
    const rows: Row[] = [
      { id: "1", label: "alpha", n: 1 },
      { id: "2", label: "beta", n: null },
    ];
    const out = await readStream(streamCsv(rows, COLUMNS));
    expect(out.charCodeAt(0)).toBe(0xfeff);
    expect(out.slice(1)).toBe("id,label,n\r\n1,alpha,1\r\n2,beta,");
  });

  it("emits header only when rows are empty", async () => {
    const out = await readStream(streamCsv<Row>([], COLUMNS));
    expect(out.slice(1)).toBe("id,label,n");
  });

  it("works with async iterables", async () => {
    async function* gen(): AsyncGenerator<Row> {
      yield { id: "1", label: "a", n: 1 };
      yield { id: "2", label: "b", n: 2 };
    }
    const out = await readStream(streamCsv(gen(), COLUMNS));
    expect(out.slice(1)).toBe("id,label,n\r\n1,a,1\r\n2,b,2");
  });

  it("matches the buffered output for the same rows", async () => {
    const rows: Row[] = [
      { id: "1", label: 'quote "x"', n: 1 },
      { id: "2", label: "comma,here", n: 2 },
    ];
    const buffered = serializeCsv(rows, COLUMNS);
    const streamed = (await readStream(streamCsv(rows, COLUMNS))).slice(1);
    expect(streamed).toBe(buffered);
  });
});

describe("csvFilenameSegment", () => {
  it("strips unsafe chars and trims", () => {
    expect(csvFilenameSegment("hello world / 2026")).toBe("hello-world-2026");
  });
});
