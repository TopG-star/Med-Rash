"use client";

import { useEffect, useRef, useState } from "react";

type SharePanelProps = {
  sessionName: string;
  joinCode: string;
  joinUrl: string | null;
  configError: string | null;
};

type Toast = { kind: "success" | "error"; message: string } | null;

/**
 * Projector-grade audience share surface for the Host Control Room. Renders a
 * large QR + giant join code so an audience can scan or type from across the
 * room. Reuses the same lazy `qrcode` strategy as `session-row-actions` and
 * degrades to a manual-copy fallback when the Clipboard API is unavailable.
 */
export function SharePanel({
  sessionName,
  joinCode,
  joinUrl,
  configError,
}: SharePanelProps) {
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [qrError, setQrError] = useState<string | null>(null);
  const [toast, setToast] = useState<Toast>(null);
  const [showFallback, setShowFallback] = useState(false);
  const fallbackInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (!joinUrl) return;
    let cancelled = false;
    (async () => {
      try {
        const QrLib = await import("qrcode");
        const dataUrl = await QrLib.toDataURL(joinUrl, {
          margin: 1,
          width: 480,
          errorCorrectionLevel: "M",
        });
        if (!cancelled) {
          setQrDataUrl(dataUrl);
          setQrError(null);
        }
      } catch {
        if (!cancelled) {
          setQrError("QR render failed — copy the join link instead.");
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [joinUrl]);

  useEffect(() => {
    if (toast === null) return;
    const timer = window.setTimeout(() => setToast(null), 2200);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    if (showFallback) {
      const id = window.requestAnimationFrame(() => {
        const input = fallbackInputRef.current;
        if (input) {
          input.focus();
          input.select();
        }
      });
      return () => window.cancelAnimationFrame(id);
    }
  }, [showFallback]);

  async function handleCopy() {
    if (!joinUrl) return;
    if (
      typeof navigator !== "undefined" &&
      navigator.clipboard &&
      typeof navigator.clipboard.writeText === "function"
    ) {
      try {
        await navigator.clipboard.writeText(joinUrl);
        setToast({ kind: "success", message: "Copied!" });
        return;
      } catch {
        // Fall through to manual-copy modal.
      }
    }
    setShowFallback(true);
  }

  function handleOpen() {
    if (!joinUrl) return;
    window.open(joinUrl, "_blank", "noopener,noreferrer");
  }

  const codeChunks = formatJoinCode(joinCode);

  return (
    <section
      className="arena-panel bg-[var(--arena-surface)] p-6"
      aria-label={`Audience share panel for ${sessionName}`}
    >
      <header className="mb-5 flex items-center justify-between gap-4">
        <h2 className="font-[family-name:var(--font-anybody)] text-2xl font-extrabold uppercase tracking-tight">
          Audience Share
        </h2>
        <span className="rounded-full bg-[var(--arena-surface-muted)] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.12em] text-[var(--arena-ink-muted)]">
          Project this screen
        </span>
      </header>

      {configError ? (
        <p
          role="status"
          className="arena-panel mb-5 border-[#ffb300] bg-[#3a2e14] p-3 text-sm font-semibold text-[#ffd88a]"
        >
          {configError}
        </p>
      ) : null}

      <div className="grid gap-6 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] md:items-center">
        <div className="flex items-center justify-center">
          <div
            className="grid place-items-center rounded-[20px] border-[3px] border-[var(--arena-outline)] bg-white p-4"
            style={{ width: 320, height: 320 }}
          >
            {!joinUrl ? (
              <p className="px-6 text-center text-xs font-semibold text-[#705d00]">
                QR unavailable until the participant base URL is configured.
              </p>
            ) : qrError ? (
              <p className="px-6 text-center text-xs font-semibold text-[#b30015]">
                {qrError}
              </p>
            ) : qrDataUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={qrDataUrl}
                alt={`QR code linking to ${joinUrl}`}
                width={288}
                height={288}
              />
            ) : (
              <p className="text-xs font-semibold text-[#705d00]">Rendering…</p>
            )}
          </div>
        </div>

        <div className="flex flex-col gap-5">
          <div>
            <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[var(--arena-ink-muted)]">
              Join code
            </p>
            <p
              className="mt-2 font-[family-name:var(--font-anybody)] text-[64px] font-extrabold leading-none tracking-[0.12em] text-[#FFDE59] md:text-[80px]"
              aria-label={`Join code ${joinCode}`}
            >
              {codeChunks}
            </p>
          </div>

          <div className="space-y-1">
            <p className="text-xs font-extrabold uppercase tracking-[0.12em] text-[var(--arena-ink-muted)]">
              Or open the link
            </p>
            <p className="break-all text-sm font-semibold text-[var(--arena-ink)]">
              {joinUrl ?? "—"}
            </p>
          </div>

          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              onClick={handleCopy}
              disabled={!joinUrl}
              className="arena-button bg-[#73F6FB] px-5 py-2 text-sm font-extrabold uppercase tracking-[0.05em] text-[#0c0c14] disabled:cursor-not-allowed disabled:opacity-40"
            >
              Copy link
            </button>
            <button
              type="button"
              onClick={handleOpen}
              disabled={!joinUrl}
              className="arena-button bg-[#FFDE59] px-5 py-2 text-sm font-extrabold uppercase tracking-[0.05em] text-[#1b1b1b] disabled:cursor-not-allowed disabled:opacity-40"
            >
              Open in tab
            </button>
          </div>
        </div>
      </div>

      {toast ? (
        <div
          role="status"
          aria-live="polite"
          className={`pointer-events-none fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-full border-[3px] border-[var(--arena-outline)] px-5 py-2 text-sm font-extrabold uppercase tracking-[0.05em] shadow-[6px_6px_0_0_var(--arena-outline)] ${
            toast.kind === "success"
              ? "bg-[var(--arena-success)] text-[#0c4a1f]"
              : "bg-[var(--arena-danger)] text-[#7a0010]"
          }`}
        >
          {toast.message}
        </div>
      ) : null}

      {showFallback ? (
        <ModalShell
          title="Copy join link"
          onClose={() => setShowFallback(false)}
        >
          <p className="text-sm text-[var(--arena-ink-muted)]">
            Clipboard access is blocked. Select the link below and copy it
            manually.
          </p>
          <input
            ref={fallbackInputRef}
            readOnly
            value={joinUrl ?? ""}
            onFocus={(event) => event.currentTarget.select()}
            className="arena-panel w-full bg-[var(--arena-surface-muted)] px-3 py-2 text-sm text-[var(--arena-ink)]"
          />
          <p className="text-xs font-bold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            Join code · {joinCode}
          </p>
        </ModalShell>
      ) : null}
    </section>
  );
}

function formatJoinCode(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length <= 4) return trimmed;
  // Insert a thin space every 3 chars so a 6-char code reads as two triplets.
  const chunks: string[] = [];
  for (let i = 0; i < trimmed.length; i += 3) {
    chunks.push(trimmed.slice(i, i + 3));
  }
  return chunks.join("\u2009");
}

type ModalShellProps = {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
};

function ModalShell({ title, onClose, children }: ModalShellProps) {
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={title}
      className="fixed inset-0 z-40 flex items-center justify-center bg-black/60 p-4"
      onClick={onClose}
    >
      <div
        className="arena-panel w-full max-w-md bg-[var(--arena-surface)] p-5"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-[family-name:var(--font-anybody)] text-lg font-extrabold uppercase tracking-tight">
            {title}
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="arena-button bg-[var(--arena-surface-muted)] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.05em]"
          >
            Close
          </button>
        </div>
        <div className="space-y-3">{children}</div>
      </div>
    </div>
  );
}
