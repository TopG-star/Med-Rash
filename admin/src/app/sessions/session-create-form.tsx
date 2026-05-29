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
      mode: String(formData.get("mode") ?? "ranked"),
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
    <div className="vp-split-grid">
      <form action={handleSubmit} className="vp-vstack-md">
        <div className="vp-form-grid cols-2">
          <label className="vp-field col-span-2">
            <span className="vp-label">Session Name</span>
            <input
              name="name"
              required
              maxLength={120}
              className="vp-input"
              placeholder="Q3 Cardiology Review"
            />
          </label>
          <label className="vp-field col-span-2">
            <span className="vp-label">Select Quiz</span>
            <select
              name="quizId"
              required
              defaultValue=""
              className="vp-select"
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
          <label className="vp-field col-span-2">
            <span className="vp-label">Host (optional)</span>
            <input
              name="hostName"
              maxLength={80}
              className="vp-input"
              placeholder="e.g. Dr. Mensah"
            />
          </label>
          <label className="vp-field col-span-2">
            <span className="vp-label">Session Mode</span>
            <select
              name="mode"
              required
              defaultValue="ranked"
              className="vp-select"
            >
              <option value="ranked">
                Ranked — single official attempt, counts on leaderboard
              </option>
              <option value="learning">
                Learning — unlimited practice, no leaderboard impact
              </option>
            </select>
            <span className="vp-help-text">
              Participants land straight in this mode. They can switch only if
              their ranked attempt is already used.
            </span>
          </label>
          <label className="vp-field">
            <span className="vp-label">Starts At (optional)</span>
            <input
              name="startsAt"
              type="datetime-local"
              className="vp-input"
            />
          </label>
          <label className="vp-field">
            <span className="vp-label">Ends At (optional)</span>
            <input name="endsAt" type="datetime-local" className="vp-input" />
          </label>
          <button
            type="submit"
            disabled={isPending || !hasQuizzes}
            className="vp-button vp-button-primary col-span-2"
          >
            {isPending ? "Creating..." : "Generate Link & QR"}
          </button>
        </div>
        {error ? (
          <p className="vp-banner vp-banner-error">{error}</p>
        ) : null}
      </form>

      <div className="vp-preview-pane">
        <h3 className="vp-preview-title">Preview Area</h3>
        {created ? (
          <div className="vp-vstack-sm">
            <p className="vp-preview-prompt">{created.sessionName}</p>
            <p className="vp-join-code-line">
              Join code · {created.joinCode}
            </p>
            <div className="vp-qr-frame">
              {created.qrDataUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={created.qrDataUrl}
                  alt={`QR code for ${created.sessionName}`}
                  width={220}
                  height={220}
                />
              ) : (
                <p className="vp-qr-placeholder-text">QR render unavailable.</p>
              )}
            </div>
            <p className="vp-join-url">{created.joinUrl}</p>
          </div>
        ) : (
          <div className="vp-qr-placeholder">
            <div className="vp-qr-placeholder-tile" />
            <p className="vp-qr-placeholder-text">
              Generate a session to preview the QR code and join link.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
