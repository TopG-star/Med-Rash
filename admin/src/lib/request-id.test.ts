import { describe, expect, it } from "vitest";

import {
  REQUEST_ID_HEADER,
  getOrMintRequestId,
  mintRequestId,
  readRequestId,
} from "./request-id";

describe("mintRequestId", () => {
  it("emits 16 hex characters", () => {
    const id = mintRequestId();
    expect(id).toMatch(/^[0-9a-f]{16}$/);
  });

  it("is unique across many mints", () => {
    const ids = new Set<string>();
    for (let i = 0; i < 1000; i++) ids.add(mintRequestId());
    expect(ids.size).toBe(1000);
  });
});

describe("readRequestId", () => {
  it("reads from a Headers object (case-insensitive)", () => {
    const h = new Headers({ "X-Request-ID": "abc123" });
    expect(readRequestId(h)).toBe("abc123");
  });

  it("reads from a plain object using the canonical lower-case key", () => {
    expect(readRequestId({ [REQUEST_ID_HEADER]: "Plain-Value-1" })).toBe(
      "plain-value-1",
    );
  });

  it("trims whitespace and lower-cases the stored value", () => {
    const h = new Headers({ "x-request-id": "  MixEdCase  " });
    expect(readRequestId(h)).toBe("mixedcase");
  });

  it("rejects values with control characters", () => {
    const h = new Headers({ "x-request-id": "abc\u0007def" });
    expect(readRequestId(h)).toBeNull();
  });

  it("rejects overlong values (>128 chars)", () => {
    const h = new Headers({ "x-request-id": "a".repeat(129) });
    expect(readRequestId(h)).toBeNull();
  });

  it("returns null when header is absent", () => {
    expect(readRequestId(new Headers())).toBeNull();
    expect(readRequestId({})).toBeNull();
  });
});

describe("getOrMintRequestId", () => {
  it("echoes a valid incoming id", () => {
    const h = new Headers({ "x-request-id": "incoming-1234" });
    expect(getOrMintRequestId(h)).toBe("incoming-1234");
  });

  it("mints a fresh id when the header is missing", () => {
    const id = getOrMintRequestId(new Headers());
    expect(id).toMatch(/^[0-9a-f]{16}$/);
  });

  it("mints a fresh id when the header fails validation", () => {
    const h = new Headers({ "x-request-id": "bad\u0001value" });
    const id = getOrMintRequestId(h);
    expect(id).toMatch(/^[0-9a-f]{16}$/);
  });
});
