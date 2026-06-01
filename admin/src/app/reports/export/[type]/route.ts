import { NextRequest } from "next/server";

import {
  csvFilenameSegment,
  serializeCsv,
  type CsvColumn,
} from "@/lib/csv-export";
import { requireAdminSession } from "@/lib/admin-session";
import {
  getAnswersExport,
  getAttemptsExport,
  getFacilityPerformance,
  getMostMissed,
  getTreatmentPerception,
  type AnswerExportRow,
  type AttemptExportRow,
  type FacilityPerformanceRow,
  type MostMissedRow,
  type ReportFilters,
  type TreatmentPerceptionRow,
} from "@/lib/reports-queries";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type ExportType =
  | "attempts"
  | "answers"
  | "most-missed"
  | "facility-performance"
  | "treatment-perception";

const SUPPORTED: ReadonlySet<ExportType> = new Set([
  "attempts",
  "answers",
  "most-missed",
  "facility-performance",
  "treatment-perception",
]);

function isExportType(value: string): value is ExportType {
  return SUPPORTED.has(value as ExportType);
}

function readFilters(req: NextRequest): ReportFilters {
  const sp = req.nextUrl.searchParams;
  const norm = (s: string | null) => {
    const v = s?.trim();
    return v && v.length > 0 ? v : null;
  };
  return {
    startsAt: norm(sp.get("startsAt")),
    endsAt: norm(sp.get("endsAt")),
    quizId: norm(sp.get("quizId")),
    sessionId: norm(sp.get("sessionId")),
    facility: norm(sp.get("facility")),
    specialty: norm(sp.get("specialty")),
  };
}

function readLimit(req: NextRequest, fallback: number, max: number): number {
  const raw = req.nextUrl.searchParams.get("limit");
  if (!raw) return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n <= 0) return fallback;
  return Math.min(n, max);
}

function csvResponse(body: string, filename: string): Response {
  // Prepend UTF-8 BOM so Excel opens the file in the correct encoding.
  const payload = `\uFEFF${body}`;
  return new Response(payload, {
    status: 200,
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${csvFilenameSegment(filename)}.csv"`,
      "Cache-Control": "no-store",
    },
  });
}

function timestampSuffix(): string {
  return new Date().toISOString().replace(/[:.]/g, "-").replace(/Z$/, "");
}

/* ---------------------------------------------------------------------------
 * Column definitions per export type. Header names are stable so downstream
 * consumers (analysts, spreadsheets) can rely on them across releases.
 * ------------------------------------------------------------------------- */

const ATTEMPTS_COLUMNS: ReadonlyArray<CsvColumn<AttemptExportRow>> = [
  { header: "attempt_id", select: (r) => r.attemptId },
  { header: "started_at", select: (r) => r.startedAt },
  { header: "completed_at", select: (r) => r.completedAt },
  { header: "mode", select: (r) => r.mode },
  { header: "origin", select: (r) => r.origin },
  { header: "score", select: (r) => r.score },
  { header: "total_questions", select: (r) => r.totalQuestions },
  { header: "time_taken_ms", select: (r) => r.timeTakenMs },
  { header: "season_key", select: (r) => r.seasonKey },
  { header: "user_id", select: (r) => r.userId },
  { header: "user_full_name", select: (r) => r.userFullName },
  { header: "user_nickname", select: (r) => r.userNickname },
  { header: "user_facility", select: (r) => r.userFacility },
  { header: "user_specialty", select: (r) => r.userSpecialty },
  { header: "user_profession", select: (r) => r.userProfession },
  { header: "quiz_id", select: (r) => r.quizId },
  { header: "quiz_slug", select: (r) => r.quizSlug },
  { header: "quiz_title", select: (r) => r.quizTitle },
  { header: "session_id", select: (r) => r.sessionId },
  { header: "session_name", select: (r) => r.sessionName },
  { header: "session_join_code", select: (r) => r.sessionJoinCode },
];

const ANSWERS_COLUMNS: ReadonlyArray<CsvColumn<AnswerExportRow>> = [
  { header: "answer_id", select: (r) => r.answerId },
  { header: "answered_at", select: (r) => r.answeredAt },
  { header: "attempt_id", select: (r) => r.attemptId },
  { header: "attempt_started_at", select: (r) => r.attemptStartedAt },
  { header: "attempt_completed_at", select: (r) => r.attemptCompletedAt },
  { header: "attempt_mode", select: (r) => r.attemptMode },
  { header: "attempt_origin", select: (r) => r.attemptOrigin },
  { header: "season_key", select: (r) => r.seasonKey },
  { header: "user_id", select: (r) => r.userId },
  { header: "user_full_name", select: (r) => r.userFullName },
  { header: "user_nickname", select: (r) => r.userNickname },
  { header: "user_facility", select: (r) => r.userFacility },
  { header: "user_specialty", select: (r) => r.userSpecialty },
  { header: "quiz_id", select: (r) => r.quizId },
  { header: "quiz_slug", select: (r) => r.quizSlug },
  { header: "quiz_title", select: (r) => r.quizTitle },
  { header: "session_id", select: (r) => r.sessionId },
  { header: "session_name", select: (r) => r.sessionName },
  { header: "session_join_code", select: (r) => r.sessionJoinCode },
  { header: "question_id", select: (r) => r.questionId },
  { header: "prompt", select: (r) => r.prompt },
  { header: "clinical_area", select: (r) => r.clinicalArea },
  { header: "selected_index", select: (r) => r.selectedIndex },
  { header: "selected_option_text", select: (r) => r.selectedOptionText },
  { header: "correct_index", select: (r) => r.correctIndex },
  { header: "is_correct", select: (r) => r.isCorrect },
  { header: "response_time_ms", select: (r) => r.responseTimeMs },
];

const MOST_MISSED_COLUMNS: ReadonlyArray<CsvColumn<MostMissedRow>> = [
  { header: "question_id", select: (r) => r.questionId },
  { header: "quiz_title", select: (r) => r.quizTitle },
  { header: "prompt", select: (r) => r.prompt },
  { header: "tags", select: (r) => r.tags },
  { header: "attempts_count", select: (r) => r.attemptsCount },
  { header: "incorrect_count", select: (r) => r.incorrectCount },
  { header: "incorrect_rate_percent", select: (r) => r.incorrectRate },
];

const FACILITY_COLUMNS: ReadonlyArray<CsvColumn<FacilityPerformanceRow>> = [
  { header: "facility", select: (r) => r.facility },
  { header: "average_score", select: (r) => r.averageScore },
  { header: "completed_attempts", select: (r) => r.completedAttempts },
  { header: "ranked_participants", select: (r) => r.rankedParticipants },
  { header: "completion_rate_percent", select: (r) => r.completionRate },
];

const TREATMENT_COLUMNS: ReadonlyArray<CsvColumn<TreatmentPerceptionRow>> = [
  { header: "clinical_area", select: (r) => r.clinicalArea },
  { header: "prompt", select: (r) => r.prompt },
  {
    header: "most_selected_wrong_option",
    select: (r) => r.mostSelectedWrongOption,
  },
  { header: "wrong_selection_count", select: (r) => r.wrongSelectionCount },
  { header: "incorrect_rate_percent", select: (r) => r.incorrectRate },
];

/* ---------------------------------------------------------------------------
 * Dispatcher
 * ------------------------------------------------------------------------- */

export async function GET(
  req: NextRequest,
  context: { params: Promise<{ type: string }> },
): Promise<Response> {
  const session = await requireAdminSession({ currentPath: "/reports" });
  const createdBy = session.role === "host" ? session.userId : null;
  const { type } = await context.params;
  if (!isExportType(type)) {
    return new Response(
      JSON.stringify({ ok: false, message: `Unknown export type '${type}'.` }),
      { status: 404, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const filters = readFilters(req);
    const suffix = timestampSuffix();

    switch (type) {
      case "attempts": {
        const limit = readLimit(req, 5000, 50000);
        const rows = await getAttemptsExport(filters, limit, { createdBy });
        return csvResponse(
          serializeCsv(rows, ATTEMPTS_COLUMNS),
          `medrash-attempts-${suffix}`,
        );
      }
      case "answers": {
        const limit = readLimit(req, 10000, 100000);
        const rows = await getAnswersExport(filters, limit, { createdBy });
        return csvResponse(
          serializeCsv(rows, ANSWERS_COLUMNS),
          `medrash-answers-${suffix}`,
        );
      }
      case "most-missed": {
        const limit = readLimit(req, 50, 500);
        const rows = await getMostMissed(
          limit,
          {
            specialty: filters.specialty,
            facility: filters.facility,
            sessionId: filters.sessionId,
            quizId: filters.quizId,
            startsAt: filters.startsAt,
            endsAt: filters.endsAt,
          },
          { createdBy },
        );
        return csvResponse(
          serializeCsv(rows, MOST_MISSED_COLUMNS),
          `medrash-most-missed-${suffix}`,
        );
      }
      case "facility-performance": {
        const limit = readLimit(req, 50, 500);
        const rows = await getFacilityPerformance(
          limit,
          { createdBy },
          {
            quizId: filters.quizId,
            sessionId: filters.sessionId,
            specialty: filters.specialty,
            facility: filters.facility,
            startsAt: filters.startsAt,
            endsAt: filters.endsAt,
          },
        );
        return csvResponse(
          serializeCsv(rows, FACILITY_COLUMNS),
          `medrash-facility-performance-${suffix}`,
        );
      }
      case "treatment-perception": {
        const limit = readLimit(req, 50, 500);
        const rows = await getTreatmentPerception(
          limit,
          { createdBy },
          {
            quizId: filters.quizId,
            sessionId: filters.sessionId,
            specialty: filters.specialty,
            facility: filters.facility,
            startsAt: filters.startsAt,
            endsAt: filters.endsAt,
          },
        );
        return csvResponse(
          serializeCsv(rows, TREATMENT_COLUMNS),
          `medrash-treatment-perception-${suffix}`,
        );
      }
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown export error.";
    return new Response(JSON.stringify({ ok: false, message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}
