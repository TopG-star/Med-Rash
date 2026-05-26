import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/admin-session";
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
  const session = await requireAdminSession({ currentPath: "/reports" });
  const createdBy = session.role === "host" ? session.userId : null;
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
      listAdminQuizzes({ scope: "all", userId: session.userId }),
      getMostMissed(
        10,
        {
          specialty: filters.specialty,
          facility: filters.facility,
          sessionId: filters.sessionId,
        },
        { createdBy },
      ),
      getFacilityPerformance(15, { createdBy }),
      getTreatmentPerception(10, { createdBy }),
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
      user={{ email: session.email, role: session.role }}
    >
      <div className="vp-scope vp-vstack vp-vstack-lg">
        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Filters</h2>
          </div>
          <p className="vp-panel-helper">
            Filters apply to BOTH the intelligence panels below and the CSV
            exports. Submit to refresh.
          </p>
          <form method="GET" action="/reports" className="vp-form-grid cols-3">
            <label className="vp-field">
              <span className="vp-label">Started on / after</span>
              <input
                type="datetime-local"
                name="startsAt"
                defaultValue={filters.startsAt ?? ""}
                className="vp-input"
              />
            </label>
            <label className="vp-field">
              <span className="vp-label">Started on / before</span>
              <input
                type="datetime-local"
                name="endsAt"
                defaultValue={filters.endsAt ?? ""}
                className="vp-input"
              />
            </label>
            <label className="vp-field">
              <span className="vp-label">Quiz</span>
              <select
                name="quizId"
                defaultValue={filters.quizId ?? ""}
                className="vp-select"
              >
                <option value="">All quizzes</option>
                {quizzes.map((q) => (
                  <option key={q.id} value={q.id}>
                    {q.title}
                  </option>
                ))}
              </select>
              {quizzesError ? (
                <span className="vp-help-text vp-trend-stat">
                  {quizzesError}
                </span>
              ) : null}
            </label>
            <label className="vp-field">
              <span className="vp-label">Specialty (exact)</span>
              <input
                type="text"
                name="specialty"
                defaultValue={filters.specialty ?? ""}
                placeholder="Emergency Medicine"
                className="vp-input"
              />
            </label>
            <label className="vp-field">
              <span className="vp-label">Facility (exact)</span>
              <input
                type="text"
                name="facility"
                defaultValue={filters.facility ?? ""}
                placeholder="Korle-Bu Teaching Hospital"
                className="vp-input"
              />
            </label>
            <label className="vp-field">
              <span className="vp-label vp-label-with-hint">
                Session ID (UUID)
                <span
                  aria-label="Find the UUID at the end of the Live view URL: /sessions/<id>/live"
                  title="Find the UUID at the end of the Live view URL: /sessions/<id>/live"
                  className="vp-info-pill"
                >
                  i
                </span>
              </span>
              <input
                type="text"
                name="sessionId"
                defaultValue={filters.sessionId ?? ""}
                placeholder="Paste session UUID"
                className="vp-input"
              />
            </label>
            <div className="col-span-3 vp-button-row-wrap">
              <button type="submit" className="vp-button vp-button-primary">
                Apply Filters
              </button>
              <Link href="/reports" className="vp-button vp-button-ghost">
                Reset
              </Link>
            </div>
          </form>
        </section>

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Downloads (CSV)</h2>
          </div>
          <p className="vp-panel-helper">
            UTF-8 with BOM (Excel-friendly). PII included — handle per the data
            governance policy.
          </p>
          <div className="vp-download-grid">
            <a
              href={buildExportHref("attempts", filters)}
              className="vp-button vp-button-primary"
            >
              Attempts CSV
            </a>
            <a
              href={buildExportHref("answers", filters)}
              className="vp-button vp-button-primary"
            >
              Detailed Answers CSV
            </a>
            <a
              href={buildExportHref("most-missed", filters)}
              className="vp-button vp-button-secondary"
            >
              Most-Missed CSV
            </a>
            <a
              href={buildExportHref("facility-performance", filters)}
              className="vp-button vp-button-secondary"
            >
              Facility Performance CSV
            </a>
            <a
              href={buildExportHref("treatment-perception", filters)}
              className="vp-button vp-button-secondary vp-span-2"
            >
              Treatment Perception CSV
            </a>
          </div>
        </section>

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">Most-Missed Questions (top 10)</h2>
          </div>
          <MostMissedTable result={mostMissedResult} />
        </section>

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">
              Facility Performance (weakest first, top 15)
            </h2>
          </div>
          <FacilityTable result={facilityResult} />
        </section>

        <section className="vp-panel">
          <div className="vp-panel-head">
            <h2 className="vp-panel-title">
              Treatment Perception Signals (top 10)
            </h2>
          </div>
          <TreatmentTable result={treatmentResult} />
        </section>
      </div>
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
      <div className="vp-banner vp-banner-error">
        {(result.reason as Error)?.message ?? "Failed to load most-missed."}
      </div>
    );
  }
  const rows = result.value;
  if (rows.length === 0) {
    return (
      <div className="vp-empty">
        <div className="vp-empty-icon">🔍</div>
        <h3 className="vp-empty-title">No answered questions match</h3>
        <p className="vp-empty-helper">
          Adjust the filters above, or wait for participants to submit attempts.
        </p>
      </div>
    );
  }
  return (
    <div className="vp-table-wrap">
      <table className="vp-table">
        <thead>
          <tr>
            <th>Quiz</th>
            <th>Prompt</th>
            <th>Tags</th>
            <th className="is-right">Attempts</th>
            <th className="is-right">Incorrect</th>
            <th className="is-right">Wrong %</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.questionId}>
              <td>{r.quizTitle}</td>
              <td>{r.prompt}</td>
              <td className="is-muted">
                {r.tags.length > 0 ? r.tags.join(", ") : "—"}
              </td>
              <td className="is-right">{formatNumber(r.attemptsCount)}</td>
              <td className="is-right">{formatNumber(r.incorrectCount)}</td>
              <td className="is-right is-strong">
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
      <div className="vp-banner vp-banner-error">
        {(result.reason as Error)?.message ??
          "Failed to load facility performance."}
      </div>
    );
  }
  const rows = result.value;
  if (rows.length === 0) {
    return (
      <div className="vp-empty">
        <div className="vp-empty-icon">🏥</div>
        <h3 className="vp-empty-title">No facility data yet</h3>
        <p className="vp-empty-helper">
          Facilities appear once participants from them complete attempts.
        </p>
      </div>
    );
  }
  return (
    <div className="vp-table-wrap">
      <table className="vp-table">
        <thead>
          <tr>
            <th>Facility</th>
            <th className="is-right">Avg Score</th>
            <th className="is-right">Completed</th>
            <th className="is-right">Ranked Players</th>
            <th className="is-right">Completion %</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.facility}>
              <td>{r.facility}</td>
              <td className="is-right">{formatNumber(r.averageScore)}</td>
              <td className="is-right">{formatNumber(r.completedAttempts)}</td>
              <td className="is-right">
                {formatNumber(r.rankedParticipants)}
              </td>
              <td className="is-right is-strong">
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
      <div className="vp-banner vp-banner-error">
        {(result.reason as Error)?.message ??
          "Failed to load treatment perception."}
      </div>
    );
  }
  const rows = result.value;
  if (rows.length === 0) {
    return (
      <div className="vp-empty">
        <div className="vp-empty-icon">💊</div>
        <h3 className="vp-empty-title">No treatment-perception data</h3>
        <p className="vp-empty-helper">
          No questions tagged &lsquo;treatment-perception&rsquo; have wrong
          answers in this window yet.
        </p>
      </div>
    );
  }
  return (
    <div className="vp-table-wrap">
      <table className="vp-table">
        <thead>
          <tr>
            <th>Clinical Area</th>
            <th>Prompt</th>
            <th>Top Wrong Option</th>
            <th className="is-right">Wrong Count</th>
            <th className="is-right">Wrong %</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r, idx) => (
            <tr key={`${r.prompt}-${idx}`}>
              <td>{r.clinicalArea ?? "—"}</td>
              <td>{r.prompt}</td>
              <td>{r.mostSelectedWrongOption}</td>
              <td className="is-right">
                {formatNumber(r.wrongSelectionCount)}
              </td>
              <td className="is-right is-strong">
                {formatPercent(r.incorrectRate)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
