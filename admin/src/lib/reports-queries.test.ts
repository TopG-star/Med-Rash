import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Capture every supabase.rpc call across tests so we can assert exactly which
// params are forwarded. Each test resets the spy + return value.
const rpcSpy = vi.fn();

vi.mock("./supabase-server", () => ({
  getAdminSupabaseClient: () => ({
    rpc: rpcSpy,
  }),
}));

import {
  getFacilityPerformance,
  getMostMissed,
  getTreatmentPerception,
} from "./reports-queries";

beforeEach(() => {
  rpcSpy.mockReset();
  rpcSpy.mockResolvedValue({ data: [], error: null });
});

afterEach(() => {
  vi.clearAllMocks();
});

describe("getMostMissed param forwarding", () => {
  it("forwards quizId, startsAt, endsAt to knowledge_gaps", async () => {
    await getMostMissed(
      10,
      {
        quizId: "quiz-123",
        sessionId: "sess-456",
        specialty: "Emergency Medicine",
        facility: "Korle-Bu",
        startsAt: "2026-01-01T00:00:00Z",
        endsAt: "2026-01-31T23:59:59Z",
      },
      { createdBy: "host-789" },
    );

    expect(rpcSpy).toHaveBeenCalledTimes(1);
    const [name, params] = rpcSpy.mock.calls[0];
    expect(name).toBe("knowledge_gaps");
    expect(params).toEqual({
      limit_count: 10,
      specialty_filter: "Emergency Medicine",
      facility_filter: "Korle-Bu",
      session_filter: "sess-456",
      created_by_filter: "host-789",
      quiz_filter: "quiz-123",
      starts_at_filter: "2026-01-01T00:00:00Z",
      ends_at_filter: "2026-01-31T23:59:59Z",
    });
  });

  it("defaults absent filters to null", async () => {
    await getMostMissed(5, {}, {});
    const params = rpcSpy.mock.calls[0][1];
    expect(params).toMatchObject({
      limit_count: 5,
      specialty_filter: null,
      facility_filter: null,
      session_filter: null,
      created_by_filter: null,
      quiz_filter: null,
      starts_at_filter: null,
      ends_at_filter: null,
    });
  });
});

describe("getFacilityPerformance param forwarding", () => {
  it("forwards every filter to facility_performance", async () => {
    await getFacilityPerformance(
      15,
      { createdBy: "host-1" },
      {
        quizId: "q-1",
        sessionId: "s-1",
        specialty: "Cardiology",
        facility: "Korle-Bu",
        startsAt: "2026-01-01T00:00:00Z",
        endsAt: "2026-02-01T00:00:00Z",
      },
    );

    const [name, params] = rpcSpy.mock.calls[0];
    expect(name).toBe("facility_performance");
    expect(params).toEqual({
      limit_count: 15,
      created_by_filter: "host-1",
      quiz_filter: "q-1",
      session_filter: "s-1",
      specialty_filter: "Cardiology",
      facility_filter: "Korle-Bu",
      starts_at_filter: "2026-01-01T00:00:00Z",
      ends_at_filter: "2026-02-01T00:00:00Z",
    });
  });

  it("defaults absent filters to null", async () => {
    await getFacilityPerformance(3, {});
    const params = rpcSpy.mock.calls[0][1];
    expect(params).toMatchObject({
      created_by_filter: null,
      quiz_filter: null,
      session_filter: null,
      specialty_filter: null,
      facility_filter: null,
      starts_at_filter: null,
      ends_at_filter: null,
    });
  });
});

describe("getTreatmentPerception param forwarding", () => {
  it("forwards every filter to treatment_perception_trends", async () => {
    await getTreatmentPerception(
      10,
      { createdBy: "host-2" },
      {
        quizId: "q-2",
        sessionId: "s-2",
        specialty: "Pulmonology",
        facility: "Ridge",
        startsAt: "2026-03-01T00:00:00Z",
        endsAt: "2026-03-31T00:00:00Z",
      },
    );

    const [name, params] = rpcSpy.mock.calls[0];
    expect(name).toBe("treatment_perception_trends");
    expect(params).toEqual({
      limit_count: 10,
      created_by_filter: "host-2",
      quiz_filter: "q-2",
      session_filter: "s-2",
      specialty_filter: "Pulmonology",
      facility_filter: "Ridge",
      starts_at_filter: "2026-03-01T00:00:00Z",
      ends_at_filter: "2026-03-31T00:00:00Z",
    });
  });

  it("defaults absent filters to null", async () => {
    await getTreatmentPerception(3, {});
    const params = rpcSpy.mock.calls[0][1];
    expect(params).toMatchObject({
      created_by_filter: null,
      quiz_filter: null,
      session_filter: null,
      specialty_filter: null,
      facility_filter: null,
      starts_at_filter: null,
      ends_at_filter: null,
    });
  });
});

describe("RPC error surfacing", () => {
  it("throws with the supabase error message", async () => {
    rpcSpy.mockResolvedValueOnce({
      data: null,
      error: { message: "boom" },
    });
    await expect(getMostMissed(10, {}, {})).rejects.toThrow(/boom/);
  });
});
