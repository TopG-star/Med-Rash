"use client";

import Link from "next/link";
import { useActionState } from "react";

import {
  initialMfaEnrollState,
  startEnrollmentAction,
  verifyEnrollmentAction,
} from "./actions";

type EnrollSectionProps = {
  email: string;
  next: string;
};

export function EnrollSection({ email, next }: EnrollSectionProps) {
  const [enrollState, startAction, startPending] = useActionState(
    startEnrollmentAction,
    initialMfaEnrollState,
  );
  const [verifyState, verifyAction, verifyPending] = useActionState(
    verifyEnrollmentAction,
    initialMfaEnrollState,
  );

  // Once the user has clicked "Start enrollment" we have a factorId +
  // QR; once they verify, we have recovery codes. We prefer the most
  // recent state object.
  const state =
    verifyState.status === "enrolled" || verifyState.status === "error"
      ? verifyState
      : enrollState;

  if (state.status === "enrolled") {
    return (
      <div className="vp-card">
        <div className="vp-signed-in">
          <p className="vp-signed-in-label">MFA enabled for</p>
          <p className="vp-signed-in-email">{email}</p>
        </div>
        <h2 className="vp-display" style={{ fontSize: "1.4rem" }}>
          Save these recovery codes
        </h2>
        <p className="vp-tagline">
          Each code works exactly once. Store them somewhere safe — a password
          manager or printed and locked away. If you lose your authenticator
          and these codes, you will need another owner to re-invite you.
        </p>
        <ul
          aria-label="Recovery codes"
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
            gap: "0.5rem",
            margin: "1rem 0",
            padding: 0,
            listStyle: "none",
            fontFamily: "ui-monospace, SFMono-Regular, monospace",
            fontSize: "1rem",
          }}
        >
          {state.recoveryCodes.map((code) => (
            <li
              key={code}
              style={{
                padding: "0.5rem 0.75rem",
                background: "rgba(255,255,255,0.05)",
                border: "1px solid rgba(255,255,255,0.12)",
                borderRadius: "0.5rem",
                letterSpacing: "0.05em",
              }}
            >
              {code}
            </li>
          ))}
        </ul>
        <Link
          href={state.nextPath}
          className="vp-button vp-button-primary"
          style={{ textAlign: "center", textDecoration: "none" }}
        >
          I&apos;ve saved them — continue
        </Link>
      </div>
    );
  }

  if (state.status === "enrolling" || (state.status === "error" && enrollState.status === "enrolling")) {
    const enrolling = state.status === "enrolling" ? state : enrollState;
    if (enrolling.status !== "enrolling") return null;
    return (
      <form action={verifyAction} className="vp-card">
        <div className="vp-signed-in">
          <p className="vp-signed-in-label">Setting up MFA for</p>
          <p className="vp-signed-in-email">{email}</p>
        </div>
        <p className="vp-tagline">
          1. Open your authenticator app and scan this QR code.
        </p>
        <div
          aria-label="MFA QR code"
          style={{
            display: "flex",
            justifyContent: "center",
            padding: "1rem",
            background: "white",
            borderRadius: "0.5rem",
            margin: "0.75rem 0",
          }}
          // The QR is an SVG string we control end-to-end (Supabase server
          // → server action → here). No untrusted input is interpolated.
          dangerouslySetInnerHTML={{ __html: enrolling.qrSvg }}
        />
        <details>
          <summary style={{ cursor: "pointer", fontSize: "0.9rem" }}>
            Can&apos;t scan? Enter the secret manually
          </summary>
          <code
            style={{
              display: "block",
              marginTop: "0.5rem",
              padding: "0.5rem",
              background: "rgba(255,255,255,0.05)",
              borderRadius: "0.25rem",
              wordBreak: "break-all",
              fontSize: "0.9rem",
            }}
          >
            {enrolling.secret}
          </code>
        </details>
        <input type="hidden" name="factor_id" value={enrolling.factorId} />
        <input type="hidden" name="next" value={next} />
        <label className="vp-field">
          <span className="vp-label">2. Enter the 6-digit code</span>
          <input
            type="text"
            name="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]*"
            minLength={6}
            maxLength={6}
            required
            autoFocus
            className="vp-input"
          />
        </label>
        <button
          type="submit"
          disabled={verifyPending}
          className="vp-button vp-button-primary"
        >
          {verifyPending ? "Verifying..." : "Verify and enable MFA"}
        </button>
        {state.status === "error" ? (
          <p className="vp-banner vp-banner-error">{state.message}</p>
        ) : null}
      </form>
    );
  }

  return (
    <form action={startAction} className="vp-card">
      <div className="vp-signed-in">
        <p className="vp-signed-in-label">Signed in as</p>
        <p className="vp-signed-in-email">{email}</p>
      </div>
      <p className="vp-tagline">
        Click below to generate a QR code. You&apos;ll scan it with your
        authenticator app, enter the 6-digit code it gives you, then save
        eight one-time recovery codes.
      </p>
      <button
        type="submit"
        disabled={startPending}
        className="vp-button vp-button-primary"
      >
        {startPending ? "Generating..." : "Start MFA setup"}
      </button>
      {state.status === "error" ? (
        <p className="vp-banner vp-banner-error">{state.message}</p>
      ) : null}
    </form>
  );
}
