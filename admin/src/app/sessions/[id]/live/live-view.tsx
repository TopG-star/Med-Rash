"use client";

import { useEffect, useRef, useState } from "react";

import { EmptyState } from "@/components/empty-state";
import { PanelCard } from "@/components/panel-card";
import type {
  SessionLiveQuestionStat,
  SessionLiveSnapshot,
} from "@/lib/session-queries";

import { SharePanel } from "./share-panel";

const POLL_INTERVAL_MS = 3000;
const COUNTDOWN_TICK_MS = 1000;

const OPTION_LETTERS = ["A", "B", "C", "D", "E", "F"] as const;

function formatRelative(iso: string | null): string {
  if (!iso) return "Waiting for first attempt…";
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return "—";
  const delta = Math.max(0, Date.now() - ms);
  if (delta < 5_000) return "just now";
  if (delta < 60_000) return `${Math.round(delta / 1000)}s ago`;
  if (delta < 3_600_000) return `${Math.round(delta / 60_000)}m ago`;
  return new Date(ms).toLocaleTimeString();
}

function formatScore(score: number, total: number): string {
  if (total <= 0) return `${score}`;
  const pct = Math.round((score / total) * 100);
  return `${score}/${total} · ${pct}%`;
}

function formatCountdown(ms: number): string {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  const pad = (v: number) => v.toString().padStart(2, "0");
  return h > 0 ? `${pad(h)}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}

type CountdownState = {
  label: string;
  value: string;
  tone: "live" | "scheduled" | "ended" | "open";
};

function deriveCountdown(
  startsAt: string | null,
  endsAt: string | null,
  nowMs: number,
): CountdownState {
  const startMs = startsAt ? Date.parse(startsAt) : null;
  const endMs = endsAt ? Date.parse(endsAt) : null;

  if (startMs && nowMs < startMs) {
    return {
      label: "Starts in",
      value: formatCountdown(startMs - nowMs),
      tone: "scheduled",
    };
  }
  if (endMs && nowMs > endMs) {
    return { label: "Ended", value: "00:00", tone: "ended" };
  }
  if (endMs) {
    return {
      label: "Ends in",
      value: formatCountdown(endMs - nowMs),
      tone: "live",
    };
  }
  return { label: "Open session", value: "—:—", tone: "open" };
}

type LiveViewProps = {
  sessionId: string;
  initial: SessionLiveSnapshot;
  joinUrl: string | null;
  joinUrlError: string | null;
};

export function LiveView({
  sessionId,
  initial,
  joinUrl,
  joinUrlError,
}: LiveViewProps) {
  const [snapshot, setSnapshot] = useState<SessionLiveSnapshot>(initial);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<number | null>(null);
  const [now, setNow] = useState<number>(() => Date.now());
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function fetchOnce() {
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;
      try {
        const res = await fetch(`/api/sessions/${sessionId}/live`, {
          signal: controller.signal,
          cache: "no-store",
        });
        if (!res.ok) {
          throw new Error(`HTTP ${res.status}`);
        }
        const data = (await res.json()) as SessionLiveSnapshot;
        if (!cancelled) {
          setSnapshot(data);
          setError(null);
          setUpdatedAt(Date.now());
        }
      } catch (err) {
        if (!cancelled && (err as Error).name !== "AbortError") {
          setError((err as Error).message);
        }
      }
    }

    const interval = setInterval(fetchOnce, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(interval);
      abortRef.current?.abort();
    };
  }, [sessionId]);

  useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), COUNTDOWN_TICK_MS);
    return () => clearInterval(tick);
  }, []);

  const countdown = deriveCountdown(snapshot.startsAt, snapshot.endsAt, now);
  const completionPct =
    snapshot.joined > 0
      ? Math.round((snapshot.submitted / snapshot.joined) * 100)
      : 0;

  return (
    <div className="host-room-dark space-y-6">
      <HeroStrip snapshot={snapshot} countdown={countdown} />

      <section className="grid gap-5 md:grid-cols-3">
        <DarkMetric
          label="Joined"
          value={snapshot.joined.toLocaleString()}
          delta={
            snapshot.scanned > snapshot.joined
              ? `${snapshot.scanned.toLocaleString()} resolved the code`
              : snapshot.isActiveNow
                ? "Session live"
                : "Not started"
          }
          accent="#FFDE59"
        />
        <DarkMetric
          label="Submitted"
          value={snapshot.submitted.toLocaleString()}
          delta={`${completionPct}% completion`}
          accent="#73F6FB"
        />
        <DarkMetric
          label="Last Activity"
          value={formatRelative(snapshot.lastActivityAt)}
          delta={
            updatedAt === null
              ? "Connecting…"
              : `Refreshed ${formatRelative(new Date(updatedAt).toISOString())}`
          }
          accent="#FFD4E7"
        />
      </section>

      {error ? (
        <p
          role="status"
          className="arena-panel border-[#ff6b6b] bg-[#3a1414] p-3 text-sm font-semibold text-[#ffd8d2]"
        >
          Live refresh failed: {error}. Retrying every 3 seconds.
        </p>
      ) : null}

      <SharePanel
        sessionName={snapshot.name}
        joinCode={snapshot.joinCode}
        joinUrl={joinUrl}
        configError={joinUrlError}
      />

      <PanelCard title="Answer Distribution">
        {snapshot.perQuestion.length === 0 ? (
          <EmptyState
            icon={<span>📡</span>}
            title="No questions yet"
            helper="Once this quiz has active questions and the first answer lands, distribution bars appear here."
          />
        ) : (
          <ol className="space-y-5">
            {snapshot.perQuestion.map((stat, index) => (
              <QuestionDistribution
                key={stat.questionId}
                index={index}
                stat={stat}
              />
            ))}
          </ol>
        )}
      </PanelCard>

      <PanelCard title="Top 5 Live">
        {snapshot.top5.length === 0 ? (
          <EmptyState
            icon={<span>📡</span>}
            title="No submissions yet"
            helper="Once your first participant submits, this leaderboard will populate within seconds."
          />
        ) : (
          <ol className="space-y-3">
            {snapshot.top5.map((row, index) => (
              <li
                key={row.participantId}
                className="arena-panel flex items-center justify-between gap-4 bg-[var(--arena-surface)] p-4"
              >
                <div className="flex items-center gap-4">
                  <span className="grid h-10 w-10 place-items-center rounded-full bg-[#FFDE59] font-[family-name:var(--font-anybody)] text-xl font-extrabold text-[#1b1b1b]">
                    {index + 1}
                  </span>
                  <div>
                    <p className="text-lg font-bold">{row.displayName}</p>
                    {row.facility ? (
                      <p className="text-xs font-semibold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
                        {row.facility}
                      </p>
                    ) : null}
                  </div>
                </div>
                <span className="font-[family-name:var(--font-anybody)] text-2xl font-extrabold">
                  {formatScore(row.score, row.totalQuestions)}
                </span>
              </li>
            ))}
          </ol>
        )}
      </PanelCard>
    </div>
  );
}

type HeroStripProps = {
  snapshot: SessionLiveSnapshot;
  countdown: CountdownState;
};

function HeroStrip({ snapshot, countdown }: HeroStripProps) {
  const toneClass =
    countdown.tone === "live"
      ? "bg-[#0e3b1e] text-[#7CFFB1]"
      : countdown.tone === "scheduled"
        ? "bg-[#2a2a4a] text-[#73F6FB]"
        : countdown.tone === "ended"
          ? "bg-[#3a1414] text-[#FFD4E7]"
          : "bg-[#20203a] text-[var(--arena-ink-muted)]";

  return (
    <section className="arena-panel flex flex-col gap-4 bg-[var(--arena-surface)] p-5 md:flex-row md:items-center md:justify-between">
      <div className="flex flex-col gap-1">
        <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[var(--arena-ink-muted)]">
          Host Control Room
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
        <span className="rounded-full border-2 border-[#FFDE59] bg-[#FFDE59] px-3 py-1 font-[family-name:var(--font-anybody)] text-sm font-extrabold uppercase tracking-[0.12em] text-[#1b1b1b]">
          Join · {snapshot.joinCode}
        </span>
        <div
          className={[
            "flex items-center gap-3 rounded-full border-2 border-[var(--arena-outline-muted)] px-4 py-2",
            toneClass,
          ].join(" ")}
        >
          <span className="text-xs font-extrabold uppercase tracking-[0.12em]">
            {countdown.label}
          </span>
          <span className="font-[family-name:var(--font-anybody)] text-xl font-extrabold tabular-nums">
            {countdown.value}
          </span>
        </div>
      </div>
    </section>
  );
}

type DarkMetricProps = {
  label: string;
  value: string;
  delta: string;
  accent: string;
};

function DarkMetric({ label, value, delta, accent }: DarkMetricProps) {
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
      <p className="mt-4 font-[family-name:var(--font-anybody)] text-4xl font-extrabold leading-none md:text-5xl">
        {value}
      </p>
      <p className="mt-3 text-sm font-semibold text-[var(--arena-ink-muted)]">
        {delta}
      </p>
    </div>
  );
}

type QuestionDistributionProps = {
  index: number;
  stat: SessionLiveQuestionStat;
};

function QuestionDistribution({ index, stat }: QuestionDistributionProps) {
  return (
    <li className="arena-panel space-y-3 bg-[var(--arena-surface)] p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-[#73F6FB] text-sm font-extrabold text-[#1b1b1b]">
            Q{index + 1}
          </span>
          <p className="text-base font-semibold leading-snug text-[var(--arena-ink)]">
            {stat.prompt}
          </p>
        </div>
        <span className="shrink-0 rounded-full bg-[var(--arena-surface-muted)] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.1em] text-[var(--arena-ink-muted)]">
          {stat.totalAnswers} {stat.totalAnswers === 1 ? "answer" : "answers"}
        </span>
      </div>
      <ul className="space-y-2">
        {stat.options.map((option, optionIndex) => {
          const count = stat.optionCounts[optionIndex] ?? 0;
          const pct =
            stat.totalAnswers > 0
              ? Math.round((count / stat.totalAnswers) * 100)
              : 0;
          const isCorrect = optionIndex === stat.correctIndex;
          const barColor = isCorrect ? "#7CFFB1" : "#73F6FB";
          const letter = OPTION_LETTERS[optionIndex] ?? `${optionIndex + 1}`;
          return (
            <li key={`${stat.questionId}-${optionIndex}`} className="space-y-1">
              <div className="flex items-center justify-between gap-3 text-sm">
                <span className="flex min-w-0 items-center gap-2">
                  <span
                    className={[
                      "grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-extrabold",
                      isCorrect
                        ? "bg-[#7CFFB1] text-[#0c0c14]"
                        : "bg-[var(--arena-surface-muted)] text-[var(--arena-ink)]",
                    ].join(" ")}
                  >
                    {letter}
                  </span>
                  <span className="truncate text-[var(--arena-ink)]">
                    {option}
                  </span>
                  {isCorrect ? (
                    <span className="shrink-0 rounded-full bg-[#0e3b1e] px-2 py-0.5 text-[10px] font-extrabold uppercase tracking-[0.1em] text-[#7CFFB1]">
                      Correct
                    </span>
                  ) : null}
                </span>
                <span className="shrink-0 font-[family-name:var(--font-anybody)] text-sm font-extrabold tabular-nums text-[var(--arena-ink)]">
                  {pct}% · {count}
                </span>
              </div>
              <div className="h-2.5 w-full overflow-hidden rounded-full bg-[var(--arena-surface-muted)]">
                <div
                  className="h-full rounded-full transition-[width] duration-500"
                  style={{
                    width: `${pct}%`,
                    backgroundColor: barColor,
                    opacity: count === 0 ? 0.25 : 1,
                  }}
                />
              </div>
            </li>
          );
        })}
      </ul>
    </li>
  );
}
