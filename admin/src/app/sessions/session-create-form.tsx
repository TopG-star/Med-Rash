"use client";

import { useMemo, useState, useTransition } from "react";

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

const DURATION_PRESETS: ReadonlyArray<{ label: string; minutes: number }> = [
  { label: "15m", minutes: 15 },
  { label: "30m", minutes: 30 },
  { label: "1h", minutes: 60 },
  { label: "2h", minutes: 120 },
  { label: "4h", minutes: 240 },
];

const CUSTOM_DURATION_KEY = "custom";

function toIsoOrNull(value: string): string | null {
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  const ms = Date.parse(trimmed);
  if (Number.isNaN(ms)) return null;
  return new Date(ms).toISOString();
}

function formatEndsAt(startsAtIso: string | null, minutes: number | null): string {
  if (!startsAtIso || !minutes || minutes <= 0) return "\u2014";
  const startMs = Date.parse(startsAtIso);
  if (Number.isNaN(startMs)) return "\u2014";
  const endMs = startMs + minutes * 60_000;
  return new Date(endMs).toLocaleString();
}

export function SessionCreateForm({ quizOptions }: Props) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<CreatedSnapshot | null>(null);

  // Local UI state for the new Start + Duration picker.
  const [startsAtRaw, setStartsAtRaw] = useState("");
  const [durationKey, setDurationKey] = useState<string>("60");
  const [customMinutesRaw, setCustomMinutesRaw] = useState<string>("45");

  const hasQuizzes = quizOptions.length > 0;

  const effectiveMinutes: number | null = useMemo(() => {
    if (durationKey === CUSTOM_DURATION_KEY) {
      const parsed = Number.parseInt(customMinutesRaw, 10);
      if (Number.isNaN(parsed) || parsed < 5 || parsed > 480) return null;
      return parsed;
    }
    const preset = Number.parseInt(durationKey, 10);
    return Number.isNaN(preset) ? null : preset;
  }, [durationKey, customMinutesRaw]);

  const startsAtIso = useMemo(() => toIsoOrNull(startsAtRaw), [startsAtRaw]);
  const endsAtPreview = formatEndsAt(startsAtIso, effectiveMinutes);
  const endsAtIso: string | null =
    startsAtIso && effectiveMinutes
      ? new Date(Date.parse(startsAtIso) + effectiveMinutes * 60_000).toISOString()
      : null;

  function handleSubmit(formData: FormData) {
    setError(null);
    const payload = {
      quizId: String(formData.get("quizId") ?? ""),
      name: String(formData.get("name") ?? ""),
      hostName: String(formData.get("hostName") ?? ""),
      startsAt: startsAtIso,
      endsAt: endsAtIso,
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
                Ranked &mdash; single official attempt, counts on leaderboard
              </option>
              <option value="learning">
                Learning &mdash; unlimited practice, no leaderboard impact
              </option>
            </select>
            <span className="vp-help-text">
              Participants land straight in this mode. They can switch only if
              their ranked attempt is already used.
            </span>
          </label>
          <label className="vp-field col-span-2">
            <span className="vp-label">Starts At (optional)</span>
            <input
              type="datetime-local"
              className="vp-input"
              value={startsAtRaw}
              onChange={(event) => setStartsAtRaw(event.target.value)}
            />
            <span className="vp-help-text">
              Leave blank to start when the first participant joins.
            </span>
          </label>
          <div className="vp-field col-span-2">
            <span className="vp-label">Duration</span>
            <div
              role="group"
              aria-label="Session duration"
              className="vp-chip-group"
            >
              {DURATION_PRESETS.map((preset) => {
                const key = String(preset.minutes);
                const selected = durationKey === key;
                return (
                  <button
                    key={key}
                    type="button"
                    aria-pressed={selected}
                    onClick={() => setDurationKey(key)}
                    className={`vp-chip-option ${selected ? "is-selected" : ""}`}
                  >
                    {preset.label}
                  </button>
                );
              })}
              <button
                type="button"
                aria-pressed={durationKey === CUSTOM_DURATION_KEY}
                onClick={() => setDurationKey(CUSTOM_DURATION_KEY)}
                className={`vp-chip-option ${durationKey === CUSTOM_DURATION_KEY ? "is-selected" : ""}`}
              >
                Custom
              </button>
            </div>
            {durationKey === CUSTOM_DURATION_KEY ? (
              <label className="vp-field vp-mt-3">
                <span className="vp-label">Custom minutes (5&ndash;480)</span>
                <input
                  type="number"
                  min={5}
                  max={480}
                  step={5}
                  inputMode="numeric"
                  className="vp-input"
                  value={customMinutesRaw}
                  onChange={(event) => setCustomMinutesRaw(event.target.value)}
                />
              </label>
            ) : null}
            <span className="vp-help-text">
              Ends at: <strong>{endsAtPreview}</strong>
              {!startsAtIso ? " (no start time set, end is open)" : ""}
            </span>
          </div>
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
