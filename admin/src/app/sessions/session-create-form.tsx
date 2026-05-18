"use client";

import { useState, useTransition } from "react";

import {
  createSessionAction,
  type CreateSessionActionResult,
} from "./actions";
import type { AdminQuizOption } from "@/lib/session-queries";

type Props = {
  quizOptions: AdminQuizOption[];
};

type CreatedSnapshot = {
  joinCode: string;
  joinUrl: string;
  qrDataUrl: string | null;
  sessionName: string;
};

function toIsoOrNull(value: string): string | null {
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  const ms = Date.parse(trimmed);
  if (Number.isNaN(ms)) return null;
  return new Date(ms).toISOString();
}

export function SessionCreateForm({ quizOptions }: Props) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<CreatedSnapshot | null>(null);

  const hasQuizzes = quizOptions.length > 0;

  function handleSubmit(formData: FormData) {
    setError(null);
    const payload = {
      quizId: String(formData.get("quizId") ?? ""),
      name: String(formData.get("name") ?? ""),
      hostName: String(formData.get("hostName") ?? ""),
      startsAt: toIsoOrNull(String(formData.get("startsAt") ?? "")),
      endsAt: toIsoOrNull(String(formData.get("endsAt") ?? "")),
    };

    startTransition(async () => {
      const result: CreateSessionActionResult = await createSessionAction(payload);
      if (!result.ok) {
        setError(result.message);
        setCreated(null);
        return;
      }

      // Render QR client-side from joinUrl to keep the server action payload
      // small and avoid bundling qrcode into the server response.
      let qrDataUrl: string | null = null;
      try {
        const QrLib = await import("qrcode");
        qrDataUrl = await QrLib.toDataURL(result.data.joinUrl, {
          margin: 1,
          width: 220,
        });
      } catch {
        qrDataUrl = null;
      }

      setCreated({
        joinCode: result.data.session.joinCode,
        joinUrl: result.data.joinUrl,
        qrDataUrl,
        sessionName: result.data.session.name,
      });
    });
  }

  return (
    <div className="grid gap-5 xl:grid-cols-[1.5fr_1fr]">
      <form action={handleSubmit} className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2">
          <label className="md:col-span-2 space-y-2">
            <span className="text-sm font-semibold">Session Name</span>
            <input
              name="name"
              required
              maxLength={120}
              className="arena-panel w-full px-4 py-3"
              placeholder="Q3 Cardiology Review"
            />
          </label>
          <label className="md:col-span-2 space-y-2">
            <span className="text-sm font-semibold">Select Quiz</span>
            <select
              name="quizId"
              required
              defaultValue=""
              className="arena-panel w-full px-4 py-3"
              disabled={!hasQuizzes}
            >
              <option value="" disabled>
                {hasQuizzes
                  ? "Pick an active quiz..."
                  : "No active quizzes available"}
              </option>
              {quizOptions.map((quiz) => (
                <option key={quiz.id} value={quiz.id}>
                  {quiz.title}
                </option>
              ))}
            </select>
          </label>
          <label className="md:col-span-2 space-y-2">
            <span className="text-sm font-semibold">Host (optional)</span>
            <input
              name="hostName"
              maxLength={80}
              className="arena-panel w-full px-4 py-3"
              placeholder="e.g. Dr. Mensah"
            />
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Starts At (optional)</span>
            <input
              name="startsAt"
              type="datetime-local"
              className="arena-panel w-full px-4 py-3"
            />
          </label>
          <label className="space-y-2">
            <span className="text-sm font-semibold">Ends At (optional)</span>
            <input
              name="endsAt"
              type="datetime-local"
              className="arena-panel w-full px-4 py-3"
            />
          </label>
          <button
            type="submit"
            disabled={isPending || !hasQuizzes}
            className="arena-button md:col-span-2 bg-[var(--arena-primary)] px-5 py-4 font-semibold disabled:opacity-60"
          >
            {isPending ? "Creating..." : "Generate Link & QR"}
          </button>
        </div>
        {error ? (
          <p className="text-sm font-semibold text-[var(--arena-danger)]">
            {error}
          </p>
        ) : null}
      </form>

      <div className="arena-panel space-y-4 bg-[var(--arena-surface)] p-6">
        <h3 className="font-[family-name:var(--font-anybody)] text-lg font-extrabold uppercase tracking-tight">
          Preview Area
        </h3>
        {created ? (
          <div className="space-y-3">
            <p className="text-sm font-semibold">{created.sessionName}</p>
            <p className="text-xs font-bold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
              Join code · {created.joinCode}
            </p>
            <div className="flex items-center justify-center rounded-[16px] border-[3px] border-[var(--arena-outline)] bg-white p-4">
              {created.qrDataUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={created.qrDataUrl}
                  alt={`QR code for ${created.sessionName}`}
                  width={220}
                  height={220}
                />
              ) : (
                <p className="text-xs font-semibold text-[var(--arena-ink-muted)]">
                  QR render unavailable.
                </p>
              )}
            </div>
            <p className="break-all text-xs font-medium text-[var(--arena-ink-muted)]">
              {created.joinUrl}
            </p>
          </div>
        ) : (
          <div className="flex min-h-72 flex-col items-center justify-center rounded-[16px] bg-[var(--arena-panel)] p-6 text-center">
            <div className="h-24 w-24 rounded-[16px] border-[3px] border-dashed border-[var(--arena-outline)] bg-[var(--arena-surface)]" />
            <p className="mt-4 font-semibold">
              Generate a session to preview the QR code and join link.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
