import { describe, expect, it } from "vitest";
import type { ErrorEvent } from "@sentry/core";

import { scrubEvent } from "./sentry-scrubber";

function baseEvent(overrides: Partial<ErrorEvent> = {}): ErrorEvent {
  return {
    type: undefined,
    event_id: "abc",
    timestamp: 0,
    ...overrides,
  } as ErrorEvent;
}

describe("sentry-scrubber", () => {
  it("removes email, username, and ip from user", () => {
    const ev = baseEvent({
      user: {
        id: "u_123",
        email: "kwame@medrash.app",
        username: "kwame",
        ip_address: "10.0.0.5",
      },
    });
    const out = scrubEvent(ev)!;
    expect(out.user).toEqual({ id: "u_123" });
  });

  it("strips query and fragment from request URL", () => {
    const ev = baseEvent({
      request: { url: "https://x/admin?token=secret&next=/dash#hash" },
    });
    const out = scrubEvent(ev)!;
    expect(out.request!.url).toBe("https://x/admin");
  });

  it("redacts cookie and authorization headers", () => {
    const ev = baseEvent({
      request: {
        url: "https://x",
        headers: {
          "Content-Type": "application/json",
          Cookie: "medrash-admin-session=abc",
          authorization: "Bearer xyz",
        },
      },
    });
    const out = scrubEvent(ev)!;
    expect(out.request!.headers).toEqual({
      "Content-Type": "application/json",
      Cookie: "[redacted]",
      authorization: "[redacted]",
    });
  });

  it("drops cookies and data fields entirely", () => {
    const ev = baseEvent({
      request: {
        url: "https://x",
        cookies: { "sb-access-token": "leak" },
        data: { password: "p@ss" },
      },
    });
    const out = scrubEvent(ev)!;
    expect(out.request!.cookies).toBeUndefined();
    expect(out.request!.data).toBeUndefined();
  });

  it("redacts email-shaped substrings in exception value and message", () => {
    const ev = baseEvent({
      message: "failed for user kwame@medrash.app",
      exception: {
        values: [
          { type: "Error", value: "rejected token for ama.b@hospital.org while parsing" },
        ],
      },
    });
    const out = scrubEvent(ev)!;
    expect(out.message).toBe("failed for user [email-redacted]");
    expect(out.exception!.values![0].value).toBe(
      "rejected token for [email-redacted] while parsing",
    );
  });

  it("scrubs breadcrumb URLs and messages", () => {
    const ev = baseEvent({
      breadcrumbs: [
        {
          category: "fetch",
          data: { url: "https://api/x?token=leak" },
          message: "called for amma@med.org",
        },
        {
          category: "navigation",
          data: { from: "/a?q=x", to: "/b?token=y" },
        },
      ],
    });
    const out = scrubEvent(ev)!;
    expect(out.breadcrumbs![0].data!.url).toBe("https://api/x");
    expect(out.breadcrumbs![0].message).toBe("called for [email-redacted]");
    expect(out.breadcrumbs![1].data!.from).toBe("/a");
    expect(out.breadcrumbs![1].data!.to).toBe("/b");
  });

  it("truncates strings longer than the cap", () => {
    const long = "a".repeat(3000);
    const ev = baseEvent({ message: long });
    const out = scrubEvent(ev)!;
    expect(out.message!.length).toBeLessThan(long.length);
    expect(out.message!.endsWith("[truncated]")).toBe(true);
  });

  it("promotes X-Request-ID header to a top-level tag", () => {
    const ev = baseEvent({
      request: {
        url: "https://x/api",
        headers: {
          "X-Request-Id": "abcDEF1234567890",
          "Content-Type": "application/json",
        },
      },
    });
    const out = scrubEvent(ev)!;
    expect(out.tags).toMatchObject({ request_id: "abcdef1234567890" });
  });

  it("does not invent a request_id tag when the header is missing", () => {
    const ev = baseEvent({
      request: { url: "https://x", headers: { "Content-Type": "x" } },
    });
    const out = scrubEvent(ev)!;
    expect(out.tags?.request_id).toBeUndefined();
  });

  it("rejects invalid X-Request-ID values (control chars / overlong)", () => {
    const ev = baseEvent({
      request: { url: "https://x", headers: { "x-request-id": "bad\u0007value" } },
    });
    const out = scrubEvent(ev)!;
    expect(out.tags?.request_id).toBeUndefined();
  });
});

