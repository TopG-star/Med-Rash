"use client";

import { useEffect, useRef, useState } from "react";

type Props = {
  sessionName: string;
  joinCode: string;
  joinUrl: string;
};

type Toast = { kind: "success" | "error"; message: string } | null;

/**
 * Per-row admin actions for a session: copy the join link to the clipboard
 * (with a manual-copy modal fallback) and reveal the QR code on demand.
 *
 * The QR is rendered client-side from `joinUrl` via the lazy-imported `qrcode`
 * package, so nothing is persisted or duplicated server-side — refreshing the
 * page or navigating away and back always recovers it.
 */
export function SessionRowActions({ sessionName, joinCode, joinUrl }: Props) {
  const [toast, setToast] = useState<Toast>(null);
  const [showFallback, setShowFallback] = useState(false);
  const [showQr, setShowQr] = useState(false);
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [qrError, setQrError] = useState<string | null>(null);
  const [qrLoading, setQrLoading] = useState(false);
  const fallbackInputRef = useRef<HTMLInputElement | null>(null);

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

  async function handleShowQr() {
    setShowQr(true);
    if (qrDataUrl || qrLoading) return;
    setQrLoading(true);
    setQrError(null);
    try {
      const QrLib = await import("qrcode");
      const dataUrl = await QrLib.toDataURL(joinUrl, { margin: 1, width: 256 });
      setQrDataUrl(dataUrl);
    } catch {
      setQrError("QR render failed — copy the join link instead.");
    } finally {
      setQrLoading(false);
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={handleCopy}
        className="arena-button bg-[var(--arena-secondary)] px-4 py-2 text-sm font-semibold"
        aria-label={`Copy join link for ${sessionName}`}
      >
        Copy link
      </button>
      <button
        type="button"
        onClick={handleShowQr}
        className="arena-button bg-[var(--arena-primary)] px-4 py-2 text-sm font-semibold"
        aria-label={`Show QR code for ${sessionName}`}
      >
        Show QR
      </button>

      {toast ? (
        <div
          role="status"
          aria-live="polite"
          className={`pointer-events-none fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-full border-[3px] border-[var(--arena-outline)] px-5 py-2 text-sm font-extrabold uppercase tracking-[0.05em] shadow-[6px_6px_0_0_var(--arena-outline)] ${
            toast.kind === "success"
              ? "bg-[var(--arena-success)] text-white"
              : "bg-[var(--arena-danger)] text-white"
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
            Clipboard access is blocked. Select the link below and copy it manually.
          </p>
          <input
            ref={fallbackInputRef}
            readOnly
            value={joinUrl}
            onFocus={(event) => event.currentTarget.select()}
            className="arena-panel w-full px-3 py-2 text-sm"
          />
          <p className="text-xs font-bold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            Join code · {joinCode}
          </p>
        </ModalShell>
      ) : null}

      {showQr ? (
        <ModalShell
          title={`QR · ${sessionName}`}
          onClose={() => setShowQr(false)}
        >
          <div className="flex items-center justify-center rounded-[16px] border-[3px] border-[var(--arena-outline)] bg-white p-4">
            {qrLoading ? (
              <p className="text-xs font-semibold text-[var(--arena-ink-muted)]">
                Rendering…
              </p>
            ) : qrError ? (
              <p className="text-xs font-semibold text-[var(--arena-danger)]">
                {qrError}
              </p>
            ) : qrDataUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={qrDataUrl}
                alt={`QR code linking to ${joinUrl}`}
                width={256}
                height={256}
              />
            ) : null}
          </div>
          <p className="text-xs font-bold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
            Join code · {joinCode}
          </p>
          <p className="break-all text-xs font-medium text-[var(--arena-ink-muted)]">
            {joinUrl}
          </p>
          <button
            type="button"
            onClick={handleCopy}
            className="arena-button bg-[var(--arena-secondary)] px-4 py-2 text-sm font-semibold"
          >
            Copy link
          </button>
        </ModalShell>
      ) : null}
    </>
  );
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
      className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4"
      onClick={onClose}
    >
      <div
        className="arena-panel w-full max-w-md space-y-3 bg-[var(--arena-surface)] p-5"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-3">
          <h3 className="font-[family-name:var(--font-anybody)] text-lg font-extrabold uppercase tracking-tight">
            {title}
          </h3>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="rounded-full border-[3px] border-[var(--arena-outline)] bg-[var(--arena-panel)] px-3 py-1 text-sm font-bold"
          >
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
