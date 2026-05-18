import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";
import { listAdminQuizzes } from "@/lib/quiz-bank-queries";
import {
  getFacilityPerformance,
  getMostMissed,
  getTreatmentPerception,
  type ReportFilters,
} from "@/lib/reports-queries";

export const dynamic = "force-dynamic";

type SearchParams = {
  startsAt?: string;
  endsAt?: string;
  quizId?: string;
  sessionId?: string;
  facility?: string;
  specialty?: string;
};

function pickString(value: string | string[] | undefined): string | null {
  if (!value) return null;
  const raw = Array.isArray(value) ? value[0] : value;
  const trimmed = raw?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

function buildExportHref(type: string, filters: ReportFilters): string {
  const sp = new URLSearchParams();
  if (filters.startsAt) sp.set("startsAt", filters.startsAt);
  if (filters.endsAt) sp.set("endsAt", filters.endsAt);
  if (filters.quizId) sp.set("quizId", filters.quizId);
  if (filters.sessionId) sp.set("sessionId", filters.sessionId);
  if (filters.facility) sp.set("facility", filters.facility);
  if (filters.specialty) sp.set("specialty", filters.specialty);
  const qs = sp.toString();
  return qs.length > 0
    ? `/reports/export/${type}?${qs}`
    : `/reports/export/${type}`;
}

function formatPercent(value: number | null): string {
  if (value === null || Number.isNaN(value)) return "—";
  return `${value.toFixed(1)}%`;
}

function formatNumber(value: number | null): string {
  if (value === null || Number.isNaN(value)) return "—";
  return value.toLocaleString();
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const filters: ReportFilters = {
    startsAt: pickString(params.startsAt),
    endsAt: pickString(params.endsAt),
    quizId: pickString(params.quizId),
    sessionId: pickString(params.sessionId),
    facility: pickString(params.facility),
    specialty: pickString(params.specialty),
  };

  // Pull intelligence panels + quiz dropdown in parallel; if any fail we
  // surface the message in-card without nuking the whole page.
  const [quizzesResult, mostMissedResult, facilityResult, treatmentResult] =
    await Promise.allSettled([
      listAdminQuizzes(),
      getMostMissed(10, {
        specialty: filters.specialty,
        facility: filters.facility,
        sessionId: filters.sessionId,
      }),
      getFacilityPerformance(15),
      getTreatmentPerception(10),
    ]);

  const quizzes =
    quizzesResult.status === "fulfilled" ? quizzesResult.value : [];
  const quizzesError =
    quizzesResult.status === "rejected"
      ? (quizzesResult.reason as Error)?.message ?? "Failed to load quizzes."
      : null;

  return (
    <AdminShell
      title="Reports"
      subtitle="Intelligence + bulk exports. All downloads stream live from Supabase via the service-role admin client."
    >
      <PanelCard title="Filters">
        <p className="text-xs font-semibold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
          Filters apply to BOTH the intelligence panels below and the CSV
          exports. Submit to refresh.
        </p>
        <form
          method="GET"
          action="/reports"
          className="grid gap-4 md:grid-cols-3"
        >
          <label className="space-y-2">
            <span className="text-sm font-semibold">Started on / after</span>
            <input
              type="datetime-local"
              name="startsAt"
              defaultValue={filters.startsAt ?? ""}
              className="arena-panel w-full px-4 py-3"
            />
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Started on / before</span>
            <input
              type="datetime-local"
              name="endsAt"
              defaultValue={filters.endsAt ?? ""}
              className="arena-panel w-full px-4 py-3"
            />
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Quiz</span>
            <select
              name="quizId"
              defaultValue={filters.quizId ?? ""}
              className="arena-panel w-full px-4 py-3"
            >
              <option value="">All quizzes</option>
              {quizzes.map((q) => (
                <option key={q.id} value={q.id}>
                  {q.title}
                </option>
              ))}
            </select>
            {quizzesError ? (
              <span className="text-xs font-semibold text-[var(--arena-danger)]">
                {quizzesError}
              </span>
            ) : null}
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Specialty (exact)</span>
            <input
              type="text"
              name="specialty"
              defaultValue={filters.specialty ?? ""}
              placeholder="Emergency Medicine"
              className="arena-panel w-full px-4 py-3"
            />
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Facility (exact)</span>
            <input
              type="text"
              name="facility"
              defaultValue={filters.facility ?? ""}
              placeholder="Korle-Bu Teaching Hospital"
              className="arena-panel w-full px-4 py-3"
            />
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Session ID (UUID)</span>
            <input
              type="text"
              name="sessionId"
              defaultValue={filters.sessionId ?? ""}
              placeholder="aaaaaaaa-aaaa-aaaa-aaaa-…"
              className="arena-panel w-full px-4 py-3"
            />
          </label>
          <div className="md:col-span-3 flex flex-wrap gap-3">
            <button
              type="submit"
              className="arena-button bg-[var(--arena-primary)] px-5 py-3 font-semibold"
            >
              Apply Filters
            </button>
            <Link
              href="/reports"
              className="arena-button bg-[var(--arena-surface)] px-5 py-3 font-semibold"
            >
              Reset
            </Link>
          </div>
        </form>
      </PanelCard>

      <PanelCard title="Downloads (CSV)">
        <p className="text-xs font-semibold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
          UTF-8 with BOM (Excel-friendly). PII included — handle per the data
          governance policy.
        </p>
        <div className="grid gap-3 md:grid-cols-2">
          <a
            href={buildExportHref("attempts", filters)}
            className="arena-button bg-[var(--arena-primary)] px-4 py-3 font-semibold"
          >
            Attempts CSV
          </a>
          <a
            href={buildExportHref("answers", filters)}
            className="arena-button bg-[var(--arena-primary)] px-4 py-3 font-semibold"
          >
            Detailed Answers CSV
          </a>
          <a
            href={buildExportHref("most-missed", filters)}
            className="arena-button bg-[var(--arena-secondary)] px-4 py-3 font-semibold"
          >
            Most-Missed CSV
          </a>
          <a
            href={buildExportHref("facility-performance", filters)}
            className="arena-button bg-[var(--arena-secondary)] px-4 py-3 font-semibold"
          >
            Facility Performance CSV
          </a>
          <a
            href={buildExportHref("treatment-perception", filters)}
            className="arena-button bg-[var(--arena-secondary)] px-4 py-3 font-semibold md:col-span-2"
          >
            Treatment Perception CSV
          </a>
        </div>
      </PanelCard>

      <PanelCard title="Most-Missed Questions (top 10)">
        <MostMissedTable result={mostMissedResult} />
      </PanelCard>

      <PanelCard title="Facility Performance (weakest first, top 15)">
        <FacilityTable result={facilityResult} />
      </PanelCard>

      <PanelCard title="Treatment Perception Signals (top 10)">
        <TreatmentTable result={treatmentResult} />
      </PanelCard>
    </AdminShell>
  );
}

function MostMissedTable({
  result,
}: {
  result: PromiseSettledResult<Awaited<ReturnType<typeof getMostMissed>>>;
}) {
  if (result.status === "rejected") {
    return (
      <p className="text-sm font-semibold text-[var(--arena-danger)]">
        {(result.reason as Error)?.message ?? "Failed to load most-missed."}
      </p>
    );
  }
  const rows = result.value;
  if (rows.length === 0) {
    return (
      <p className="text-sm font-semibold text-[var(--arena-ink-muted)]">
        No answered questions match the current filters yet.
      </p>
    );
  }
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="text-left text-xs font-extrabold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            <th className="pb-2 pr-3">Quiz</th>
            <th className="pb-2 pr-3">Prompt</th>
            <th className="pb-2 pr-3">Tags</th>
            <th className="pb-2 pr-3 text-right">Attempts</th>
            <th className="pb-2 pr-3 text-right">Incorrect</th>
            <th className="pb-2 text-right">Wrong %</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr
              key={r.questionId}
              className="border-t border-[var(--arena-outline)]"
            >
              <td className="py-2 pr-3 align-top">{r.quizTitle}</td>
              <td className="py-2 pr-3 align-top">{r.prompt}</td>
              <td className="py-2 pr-3 align-top text-xs">
                {r.tags.length > 0 ? r.tags.join(", ") : "—"}
              </td>
              <td className="py-2 pr-3 align-top text-right">
                {formatNumber(r.attemptsCount)}
              </td>
              <td className="py-2 pr-3 align-top text-right">
                {formatNumber(r.incorrectCount)}
              </td>
              <td className="py-2 align-top text-right font-semibold">
                {formatPercent(r.incorrectRate)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function FacilityTable({
  result,
}: {
  result: PromiseSettledResult<
    Awaited<ReturnType<typeof getFacilityPerformance>>
  >;
}) {
  if (result.status === "rejected") {
    return (
      <p className="text-sm font-semibold text-[var(--arena-danger)]">
        {(result.reason as Error)?.message ??
          "Failed to load facility performance."}
      </p>
    );
  }
  const rows = result.value;
  if (rows.length === 0) {
    return (
      <p className="text-sm font-semibold text-[var(--arena-ink-muted)]">
        No facility data yet.
      </p>
    );
  }
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="text-left text-xs font-extrabold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            <th className="pb-2 pr-3">Facility</th>
            <th className="pb-2 pr-3 text-right">Avg Score</th>
            <th className="pb-2 pr-3 text-right">Completed</th>
            <th className="pb-2 pr-3 text-right">Ranked Players</th>
            <th className="pb-2 text-right">Completion %</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr
              key={r.facility}
              className="border-t border-[var(--arena-outline)]"
            >
              <td className="py-2 pr-3 align-top">{r.facility}</td>
              <td className="py-2 pr-3 align-top text-right">
                {formatNumber(r.averageScore)}
              </td>
              <td className="py-2 pr-3 align-top text-right">
                {formatNumber(r.completedAttempts)}
              </td>
              <td className="py-2 pr-3 align-top text-right">
                {formatNumber(r.rankedParticipants)}
              </td>
              <td className="py-2 align-top text-right font-semibold">
                {formatPercent(r.completionRate)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function TreatmentTable({
  result,
}: {
  result: PromiseSettledResult<
    Awaited<ReturnType<typeof getTreatmentPerception>>
  >;
}) {
  if (result.status === "rejected") {
    return (
      <p className="text-sm font-semibold text-[var(--arena-danger)]">
        {(result.reason as Error)?.message ??
          "Failed to load treatment perception."}
      </p>
    );
  }
  const rows = result.value;
  if (rows.length === 0) {
    return (
      <p className="text-sm font-semibold text-[var(--arena-ink-muted)]">
        No questions tagged <code>treatment-perception</code> have wrong
        answers yet.
      </p>
    );
  }
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="text-left text-xs font-extrabold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            <th className="pb-2 pr-3">Clinical Area</th>
            <th className="pb-2 pr-3">Prompt</th>
            <th className="pb-2 pr-3">Top Wrong Option</th>
            <th className="pb-2 pr-3 text-right">Wrong Count</th>
            <th className="pb-2 text-right">Wrong %</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r, idx) => (
            <tr
              key={`${r.prompt}-${idx}`}
              className="border-t border-[var(--arena-outline)]"
            >
              <td className="py-2 pr-3 align-top">{r.clinicalArea ?? "—"}</td>
              <td className="py-2 pr-3 align-top">{r.prompt}</td>
              <td className="py-2 pr-3 align-top">
                {r.mostSelectedWrongOption}
              </td>
              <td className="py-2 pr-3 align-top text-right">
                {formatNumber(r.wrongSelectionCount)}
              </td>
              <td className="py-2 align-top text-right font-semibold">
                {formatPercent(r.incorrectRate)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
