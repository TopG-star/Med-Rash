"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { disableMfaAction } from "../../onboarding/mfa/actions";

export function DisableMfaForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [pending, startTransition] = useTransition();

  function handleClick() {
    setError(null);
    // Last-line confirmation — Disable MFA wipes every TOTP factor on the
    // account and immediately drops the session to AAL1.
    const ok = window.confirm(
      "Disable two-factor authentication? You'll need to re-enroll a new authenticator on your next sign-in. Recovery codes will be invalidated.",
    );
    if (!ok) return;
    startTransition(async () => {
      const result = await disableMfaAction();
      if (!result.ok) {
        setError(result.message);
        return;
      }
      setDone(true);
      router.refresh();
    });
  }

  if (done) {
    return (
      <p className="vp-banner vp-banner-success">
        MFA disabled. Re-enroll a fresh authenticator at{" "}
        <a className="vp-link" href="/onboarding/mfa">
          /onboarding/mfa
        </a>{" "}
        before your next privileged action.
      </p>
    );
  }

  return (
    <div className="vp-vstack vp-vstack-sm">
      <button
        type="button"
        onClick={handleClick}
        disabled={pending}
        className="vp-button vp-button-danger"
      >
        {pending ? "Disabling…" : "Disable two-factor authentication"}
      </button>
      {error ? <p className="vp-banner vp-banner-error">{error}</p> : null}
    </div>
  );
}
