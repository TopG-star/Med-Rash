import { notFound } from "next/navigation";
import Link from "next/link";

import { AdminShell } from "@/components/admin-shell";
import { PanelCard } from "@/components/panel-card";
import { requireAdminSession } from "@/lib/admin-session";
import { getSessionLiveSnapshot } from "@/lib/session-queries";

import { RecapExport } from "./recap-export";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = {
  params: Promise<{ id: string }>;
};

type RecapStatus =
  | { kind: "scheduled"; startsAt: string }
  | { kind: "live"; endsAt: string | null }
  | { kind: "ended"; endsAt: string }
  | { kind: "open" };

function resolveStatus(
  startsAt: string | null,
  endsAt: string | null,
  nowMs: number,
): RecapStatus {
  const startMs = startsAt ? Date.parse(startsAt) : null;
  const endMs = endsAt ? Date.parse(endsAt) : null;
  if (startMs && nowMs < startMs) {
    return { kind: "scheduled", startsAt: startsAt as string };
  }
  if (endMs && nowMs > endMs) {
    return { kind: "ended", endsAt: endsAt as string };
  }
  if (endMs) {
    return { kind: "live", endsAt: endsAt };
  }
  return { kind: "open" };
}

function formatDuration(startsAt: string | null, endsAt: string | null): string {
  if (!startsAt || !endsAt) return "—";
  const startMs = Date.parse(startsAt);
  const endMs = Date.parse(endsAt);
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
    return "—";
  }
  const totalSeconds = Math.floor((endMs - startMs) / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

function formatTimestamp(iso: string | null): string {
  if (!iso) return "—";
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return "—";
  return new Date(ms).toLocaleString();
}

export default async function SessionRecapPage({ params }: PageProps) {
  const { id } = await params;
  const session = await requireAdminSession({
    currentPath: `/sessions/${id}/recap`,
  });
  const snapshot = await getSessionLiveSnapshot(id);

  if (!snapshot) {
    notFound();
  }

  // Server component renders per-request (force-dynamic above), so reading the
  // wall clock here is intentional — recap status flips as time passes.
  // eslint-disable-next-line react-hooks/purity
  const status = resolveStatus(snapshot.startsAt, snapshot.endsAt, Date.now());
  const completionPct =
    snapshot.joined > 0
      ? Math.round((snapshot.submitted / snapshot.joined) * 100)
      : 0;
  const duration = formatDuration(snapshot.startsAt, snapshot.endsAt);

  // Knowledge gaps: questions ordered by correct-answer % ascending, with at
  // least one answer recorded. Surfaces what cohorts still misunderstand.
  const gaps = snapshot.perQuestion
    .filter((q) => q.totalAnswers > 0)
    .map((q) => {
      const correctCount = q.optionCounts[q.correctIndex] ?? 0;
      const correctPct = Math.round((correctCount / q.totalAnswers) * 100);
      return { ...q, correctCount, correctPct };
    })
    .sort((a, b) => a.correctPct - b.correctPct)
    .slice(0, 5);

  const statusBadge = (() => {
    switch (status.kind) {
      case "scheduled":
        return {
          tone: "bg-[#2a2a4a] text-[#73F6FB]",
          label: `Starts ${formatTimestamp(status.startsAt)}`,
        };
      case "live":
        return {
          tone: "bg-[#0e3b1e] text-[#7CFFB1]",
          label: status.endsAt
            ? `Live · ends ${formatTimestamp(status.endsAt)}`
            : "Live · open session",
        };
      case "ended":
        return {
          tone: "bg-[#3a1414] text-[#FFD4E7]",
          label: `Ended ${formatTimestamp(status.endsAt)}`,
        };
      case "open":
        return {
          tone: "bg-[#20203a] text-[var(--arena-ink-muted)]",
          label: "Open session · no end time",
        };
    }
  })();

  return (
    <AdminShell
      title={`Session Recap · ${snapshot.name}`}
      subtitle={`Final standings, knowledge gaps, and export for ${snapshot.quizTitle}.`}
      user={{ email: session.email, role: session.role }}
    >
      <div className="host-room-dark space-y-6">
        <section className="arena-panel flex flex-col gap-4 bg-[var(--arena-surface)] p-5 md:flex-row md:items-center md:justify-between">
          <div className="flex flex-col gap-1">
            <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[var(--arena-ink-muted)]">
              Session Recap
            </p>
            <h1 className="font-[family-name:var(--font-anybody)] text-2xl font-extrabold uppercase tracking-tight md:text-3xl">
              {snapshot.name}
            </h1>
            <p className="text-sm text-[var(--arena-ink-muted)]">
              {snapshot.quizTitle}
              {snapshot.hostName ? ` · Hosted by ${snapshot.hostName}` : ""}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <span
              className={[
                "rounded-full border-2 border-[var(--arena-outline-muted)] px-4 py-2 text-xs font-extrabold uppercase tracking-[0.1em]",
                statusBadge.tone,
              ].join(" ")}
            >
              {statusBadge.label}
            </span>
            <Link
              href={`/sessions/${id}/live`}
              className="arena-button bg-[#73F6FB] px-4 py-2 text-sm font-extrabold uppercase tracking-[0.05em] text-[#0c0c14]"
            >
              Open control room
            </Link>
          </div>
        </section>

        <section className="grid gap-5 md:grid-cols-4">
          <RecapMetric
            label="Participants"
            value={snapshot.joined.toLocaleString()}
            sub={`${snapshot.scanned.toLocaleString()} scanned`}
            accent="#FFDE59"
          />
          <RecapMetric
            label="Submitted"
            value={snapshot.submitted.toLocaleString()}
            sub={`${completionPct}% completion`}
            accent="#73F6FB"
          />
          <RecapMetric
            label="Questions"
            value={snapshot.totalQuestions.toLocaleString()}
            sub={
              gaps.length > 0
                ? `${gaps.length} flagged below`
                : "Awaiting answers"
            }
            accent="#FFD4E7"
          />
          <RecapMetric
            label="Duration"
            value={duration}
            sub={
              snapshot.startsAt && snapshot.endsAt
                ? `${formatTimestamp(snapshot.startsAt)} → ${formatTimestamp(
                    snapshot.endsAt,
                  )}`
                : "Open session"
            }
            accent="#7CFFB1"
          />
        </section>

        <PanelCard title="Final Standings">
          {snapshot.standings.length === 0 ? (
            <p className="text-sm text-[var(--arena-ink-muted)]">
              No completed attempts yet. Once participants submit, the
              leaderboard will fill in here.
            </p>
          ) : (
            <div className="flex flex-col gap-4">
              <div className="flex items-center justify-between">
                <p className="text-xs font-extrabold uppercase tracking-[0.12em] text-[var(--arena-ink-muted)]">
                  {snapshot.standings.length}{" "}
                  {snapshot.standings.length === 1 ? "finisher" : "finishers"}
                </p>
                <RecapExport
                  sessionName={snapshot.name}
                  joinCode={snapshot.joinCode}
                  standings={snapshot.standings}
                />
              </div>
              <ol className="space-y-2">
                {snapshot.standings.map((row, index) => {
                  const pct =
                    row.totalQuestions > 0
                      ? Math.round((row.score / row.totalQuestions) * 100)
                      : 0;
                  const rankColor =
                    index === 0
                      ? "bg-[#FFDE59] text-[#1b1b1b]"
                      : index === 1
                        ? "bg-[#73F6FB] text-[#0c0c14]"
                        : index === 2
                          ? "bg-[#FFD4E7] text-[#1b1b1b]"
                          : "bg-[var(--arena-surface-muted)] text-[var(--arena-ink)]";
                  return (
                    <li
                      key={`${row.participantId}-${index}`}
                      className="arena-panel grid grid-cols-[48px_minmax(0,1fr)_auto_auto] items-center gap-4 bg-[var(--arena-surface)] p-3"
                    >
                      <span
                        className={[
                          "grid h-10 w-10 place-items-center rounded-full font-[family-name:var(--font-anybody)] text-lg font-extrabold",
                          rankColor,
                        ].join(" ")}
                      >
                        {index + 1}
                      </span>
                      <div className="min-w-0">
                        <p className="truncate text-sm font-bold text-[var(--arena-ink)]">
                          {row.displayName}
                        </p>
                        {row.facility ? (
                          <p className="truncate text-[11px] font-semibold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
                            {row.facility}
                          </p>
                        ) : null}
                      </div>
                      <span className="font-[family-name:var(--font-anybody)] text-lg font-extrabold tabular-nums text-[var(--arena-ink)]">
                        {row.score}/{row.totalQuestions}
                      </span>
                      <span className="font-[family-name:var(--font-anybody)] text-lg font-extrabold tabular-nums text-[#FFDE59]">
                        {pct}%
                      </span>
                    </li>
                  );
                })}
              </ol>
            </div>
          )}
        </PanelCard>

        <PanelCard title="Knowledge Gaps">
          {gaps.length === 0 ? (
            <p className="text-sm text-[var(--arena-ink-muted)]">
              No answered questions yet — once attempts come in, the questions
              with the lowest correct-answer rate appear here.
            </p>
          ) : (
            <ol className="space-y-3">
              {gaps.map((q) => {
                const correctOption = q.options[q.correctIndex] ?? "—";
                const tone =
                  q.correctPct < 40
                    ? "text-[#ff8aa0]"
                    : q.correctPct < 70
                      ? "text-[#ffd88a]"
                      : "text-[#7CFFB1]";
                return (
                  <li
                    key={q.questionId}
                    className="arena-panel space-y-2 bg-[var(--arena-surface)] p-4"
                  >
                    <div className="flex items-start justify-between gap-4">
                      <p className="text-base font-semibold leading-snug text-[var(--arena-ink)]">
                        {q.prompt}
                      </p>
                      <div className="shrink-0 text-right">
                        <p
                          className={[
                            "font-[family-name:var(--font-anybody)] text-3xl font-extrabold leading-none",
                            tone,
                          ].join(" ")}
                        >
                          {q.correctPct}%
                        </p>
                        <p className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-[var(--arena-ink-muted)]">
                          correct
                        </p>
                      </div>
                    </div>
                    <div className="flex flex-wrap items-center gap-2 text-xs">
                      <span className="rounded-full bg-[#0e3b1e] px-2 py-0.5 font-extrabold uppercase tracking-[0.1em] text-[#7CFFB1]">
                        Correct answer
                      </span>
                      <span className="font-semibold text-[var(--arena-ink)]">
                        {correctOption}
                      </span>
                      <span className="text-[var(--arena-ink-muted)]">
                        · {q.correctCount}/{q.totalAnswers} got this right
                      </span>
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
        </PanelCard>
      </div>
    </AdminShell>
  );
}

type RecapMetricProps = {
  label: string;
  value: string;
  sub: string;
  accent: string;
};

function RecapMetric({ label, value, sub, accent }: RecapMetricProps) {
  return (
    <div className="arena-panel relative overflow-hidden p-5">
      <span
        aria-hidden
        className="absolute left-0 top-0 h-full w-1.5"
        style={{ backgroundColor: accent }}
      />
      <p
        className="text-xs font-extrabold uppercase tracking-[0.12em]"
        style={{ color: accent }}
      >
        {label}
      </p>
      <p className="mt-4 font-[family-name:var(--font-anybody)] text-4xl font-extrabold leading-none">
        {value}
      </p>
      <p className="mt-3 text-xs font-semibold text-[var(--arena-ink-muted)]">
        {sub}
      </p>
    </div>
  );
}
