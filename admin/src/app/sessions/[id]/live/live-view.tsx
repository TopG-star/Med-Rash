"use client";

import { useEffect, useRef, useState } from "react";

import { MetricCard } from "@/components/metric-card";
import { PanelCard } from "@/components/panel-card";
import { EmptyState } from "@/components/empty-state";
import type { SessionLiveSnapshot } from "@/lib/session-queries";

const POLL_INTERVAL_MS = 3000;

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

type LiveViewProps = {
  sessionId: string;
  initial: SessionLiveSnapshot;
};

export function LiveView({ sessionId, initial }: LiveViewProps) {
  const [snapshot, setSnapshot] = useState<SessionLiveSnapshot>(initial);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<number | null>(null);
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

  return (
    <div className="space-y-6">
      <section className="grid gap-5 md:grid-cols-3">
        <MetricCard
          label="Joined"
          value={snapshot.joined.toLocaleString()}
          delta={snapshot.isActiveNow ? "Session live" : "Session not active"}
          subtitle={
            snapshot.scanned > 0
              ? `${snapshot.scanned.toLocaleString()} ${snapshot.scanned === 1 ? "device" : "devices"} resolved this code`
              : undefined
          }
          tone="primary"
        />
        <MetricCard
          label="Submitted"
          value={snapshot.submitted.toLocaleString()}
          delta={`${snapshot.quizTitle}`}
          tone="secondary"
        />
        <MetricCard
          label="Last Activity"
          value={formatRelative(snapshot.lastActivityAt)}
          delta={
            updatedAt === null
              ? "Connecting…"
              : `Updated ${formatRelative(new Date(updatedAt).toISOString())}`
          }
          tone="tertiary"
        />
      </section>

      {error ? (
        <p
          role="status"
          className="arena-panel border-[var(--arena-danger)] bg-[var(--arena-danger)] p-3 text-sm font-semibold"
        >
          Live refresh failed: {error}. Retrying every 3 seconds.
        </p>
      ) : null}

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
                  <span className="grid h-10 w-10 place-items-center rounded-full bg-[var(--arena-primary)] font-[family-name:var(--font-anybody)] text-xl font-extrabold">
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
