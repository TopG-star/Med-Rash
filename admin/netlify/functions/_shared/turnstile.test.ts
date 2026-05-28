import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { extractRemoteIp, verifyTurnstileToken } from "./turnstile";

const ORIGINAL_ENV = { ...process.env };
const ORIGINAL_FETCH = globalThis.fetch;

beforeEach(() => {
  process.env.MEDRASH_TURNSTILE_SECRET = "test-secret";
  delete process.env.MEDRASH_TURNSTILE_BYPASS_TOKEN;
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  globalThis.fetch = ORIGINAL_FETCH;
  vi.restoreAllMocks();
});

function mockFetchOnce(payload: unknown, init?: { status?: number }) {
  const status = init?.status ?? 200;
  const body = typeof payload === "string" ? payload : JSON.stringify(payload);
  globalThis.fetch = vi.fn(async () =>
    new Response(body, {
      status,
      headers: { "content-type": "application/json" },
    }),
  ) as unknown as typeof fetch;
}

describe("verifyTurnstileToken", () => {
  it("returns ok=true when siteverify reports success", async () => {
    mockFetchOnce({ success: true });
    const result = await verifyTurnstileToken("abc-token", "1.2.3.4");
    expect(result.ok).toBe(true);
    expect(result.errorCodes).toEqual([]);
  });

  it("forwards the secret, response, and remoteip in the form body", async () => {
    const fetchSpy = vi.fn(async () =>
      new Response(JSON.stringify({ success: true }), { status: 200 }),
    ) as unknown as typeof fetch;
    globalThis.fetch = fetchSpy;
    await verifyTurnstileToken("abc-token", "1.2.3.4");
    const [, init] = (fetchSpy as unknown as { mock: { calls: [string, RequestInit][] } }).mock.calls[0];
    expect(init.method).toBe("POST");
    const body = init.body as string;
    const params = new URLSearchParams(body);
    expect(params.get("secret")).toBe("test-secret");
    expect(params.get("response")).toBe("abc-token");
    expect(params.get("remoteip")).toBe("1.2.3.4");
  });

  it("returns ok=false with siteverify error codes when not successful", async () => {
    mockFetchOnce({ success: false, "error-codes": ["invalid-input-response"] });
    const result = await verifyTurnstileToken("bad-token");
    expect(result.ok).toBe(false);
    expect(result.errorCodes).toEqual(["invalid-input-response"]);
  });

  it("rejects an empty token without calling fetch", async () => {
    const fetchSpy = vi.fn();
    globalThis.fetch = fetchSpy as unknown as typeof fetch;
    const result = await verifyTurnstileToken("");
    expect(result.ok).toBe(false);
    expect(result.errorCodes).toContain("missing-input-response");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns ok=false when MEDRASH_TURNSTILE_SECRET is missing", async () => {
    delete process.env.MEDRASH_TURNSTILE_SECRET;
    const result = await verifyTurnstileToken("anything");
    expect(result.ok).toBe(false);
    expect(result.errorCodes).toContain("missing-input-secret");
  });

  it("honors MEDRASH_TURNSTILE_BYPASS_TOKEN for hosted smoke tests", async () => {
    process.env.MEDRASH_TURNSTILE_BYPASS_TOKEN = "smoke-bypass";
    const fetchSpy = vi.fn();
    globalThis.fetch = fetchSpy as unknown as typeof fetch;
    const result = await verifyTurnstileToken("smoke-bypass");
    expect(result.ok).toBe(true);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns ok=false on siteverify HTTP error", async () => {
    mockFetchOnce("oops", { status: 502 });
    const result = await verifyTurnstileToken("token");
    expect(result.ok).toBe(false);
    expect(result.errorCodes[0]).toMatch(/siteverify-http-502/);
  });

  it("returns ok=false on fetch network error", async () => {
    globalThis.fetch = vi.fn(async () => {
      throw new Error("ECONNRESET");
    }) as unknown as typeof fetch;
    const result = await verifyTurnstileToken("token");
    expect(result.ok).toBe(false);
    expect(result.errorCodes).toContain("network-error");
  });

  it("returns ok=false when siteverify body is not JSON", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response("<html>", { status: 200 }),
    ) as unknown as typeof fetch;
    const result = await verifyTurnstileToken("token");
    expect(result.ok).toBe(false);
    expect(result.errorCodes).toContain("siteverify-bad-json");
  });
});

describe("extractRemoteIp", () => {
  it("prefers x-nf-client-connection-ip", () => {
    expect(
      extractRemoteIp({
        "x-nf-client-connection-ip": "9.9.9.9",
        "x-forwarded-for": "1.1.1.1",
      }),
    ).toBe("9.9.9.9");
  });

  it("falls back to cf-connecting-ip", () => {
    expect(
      extractRemoteIp({ "cf-connecting-ip": "8.8.8.8" }),
    ).toBe("8.8.8.8");
  });

  it("falls back to first x-forwarded-for entry", () => {
    expect(
      extractRemoteIp({ "x-forwarded-for": "1.1.1.1, 2.2.2.2" }),
    ).toBe("1.1.1.1");
  });

  it("returns null when no header matches", () => {
    expect(extractRemoteIp({})).toBeNull();
    expect(extractRemoteIp(undefined)).toBeNull();
  });
});
