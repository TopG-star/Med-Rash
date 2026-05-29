"use client";

import { useActionState, useState } from "react";

import {
  challengeAction,
  useRecoveryAction,
} from "./actions";
import {
  initialMfaChallengeState,
  initialMfaRecoveryState,
} from "./state";

type ChallengeSectionProps = {
  email: string;
  next: string;
};

export function ChallengeSection({ email, next }: ChallengeSectionProps) {
  const [mode, setMode] = useState<"code" | "recovery">("code");
  const [codeState, codeAction, codePending] = useActionState(
    challengeAction,
    initialMfaChallengeState,
  );
  const [recoveryState, recoveryAction, recoveryPending] = useActionState(
    useRecoveryAction,
    initialMfaRecoveryState,
  );

  if (mode === "recovery") {
    return (
      <form action={recoveryAction} className="vp-card">
        <div className="vp-signed-in">
          <p className="vp-signed-in-label">Recovering MFA for</p>
          <p className="vp-signed-in-email">{email}</p>
        </div>
        <p className="vp-tagline">
          Enter one of the recovery codes you saved during MFA setup. After
          you submit, your existing TOTP factor will be removed and you&apos;ll
          re-enroll on the next screen.
        </p>
        <label className="vp-field">
          <span className="vp-label">Recovery code</span>
          <input
            type="text"
            name="recovery_code"
            required
            autoFocus
            placeholder="XXXX-XXXX-XXXX"
            autoComplete="off"
            spellCheck={false}
            className="vp-input"
            style={{ fontFamily: "ui-monospace, SFMono-Regular, monospace", letterSpacing: "0.05em" }}
          />
        </label>
        <button
          type="submit"
          disabled={recoveryPending}
          className="vp-button vp-button-primary"
        >
          {recoveryPending ? "Verifying..." : "Use recovery code"}
        </button>
        <button
          type="button"
          onClick={() => setMode("code")}
          className="vp-button"
          style={{ marginTop: "0.5rem" }}
        >
          Back to code entry
        </button>
        {recoveryState.status === "error" ? (
          <p className="vp-banner vp-banner-error">{recoveryState.message}</p>
        ) : null}
      </form>
    );
  }

  return (
    <form action={codeAction} className="vp-card">
      <div className="vp-signed-in">
        <p className="vp-signed-in-label">Verifying MFA for</p>
        <p className="vp-signed-in-email">{email}</p>
      </div>
      <input type="hidden" name="next" value={next} />
      <label className="vp-field">
        <span className="vp-label">6-digit code from your authenticator</span>
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
        disabled={codePending}
        className="vp-button vp-button-primary"
      >
        {codePending ? "Verifying..." : "Verify"}
      </button>
      <button
        type="button"
        onClick={() => setMode("recovery")}
        className="vp-button"
        style={{ marginTop: "0.5rem" }}
      >
        Lost access? Use a recovery code
      </button>
      {codeState.status === "error" ? (
        <p className="vp-banner vp-banner-error">{codeState.message}</p>
      ) : null}
    </form>
  );
}
