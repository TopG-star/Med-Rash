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
        className="vp-button vp-button-ghost vp-button-sm"
        aria-label={`Copy join link for ${sessionName}`}
      >
        Copy link
      </button>
      <button
        type="button"
        onClick={handleShowQr}
        className="vp-button vp-button-primary vp-button-sm"
        aria-label={`Show QR code for ${sessionName}`}
      >
        Show QR
      </button>

      {toast ? (
        <div
          role="status"
          aria-live="polite"
          className={`vp-toast ${toast.kind === "success" ? "is-success" : "is-error"}`}
        >
          {toast.message}
        </div>
      ) : null}

      {showFallback ? (
        <ModalShell
          title="Copy join link"
          onClose={() => setShowFallback(false)}
        >
          <p className="vp-modal-text">
            Clipboard access is blocked. Select the link below and copy it
            manually.
          </p>
          <input
            ref={fallbackInputRef}
            readOnly
            value={joinUrl}
            onFocus={(event) => event.currentTarget.select()}
            className="vp-input"
          />
          <p className="vp-join-code-line">Join code · {joinCode}</p>
        </ModalShell>
      ) : null}

      {showQr ? (
        <ModalShell title={`QR · ${sessionName}`} onClose={() => setShowQr(false)}>
          <div className="vp-qr-frame">
            {qrLoading ? (
              <p className="vp-qr-placeholder-text">Rendering…</p>
            ) : qrError ? (
              <p className="vp-banner vp-banner-error">{qrError}</p>
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
          <p className="vp-join-code-line">Join code · {joinCode}</p>
          <p className="vp-join-url">{joinUrl}</p>
          <button
            type="button"
            onClick={handleCopy}
            className="vp-button vp-button-secondary vp-button-sm"
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
      className="vp-scope vp-modal-backdrop"
      onClick={onClose}
    >
      <div
        className="vp-modal-shell"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="vp-modal-head">
          <h3 className="vp-modal-title">{title}</h3>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="vp-modal-close"
          >
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
