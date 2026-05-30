"use client";

import { useState, useTransition } from "react";

import { closeSessionAction } from "./actions";

type Props = {
  sessionId: string;
  sessionName: string;
  isClosed: boolean;
};

/**
 * "End session now" button for the Sessions list. Calls the
 * closeSessionAction server action which stamps closed_at = now() and
 * revalidates the listing.
 *
 * Idempotent on the server side (already-closed sessions return
 * `alreadyClosed: true`), so a double-click is harmless.
 */
export function CloseSessionButton({ sessionId, sessionName, isClosed }: Props) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  if (isClosed) {
    return (
      <span className="vp-button vp-button-ghost vp-button-sm vp-disabled-soft">
        Ended
      </span>
    );
  }

  function handleClose() {
    setError(null);
    if (typeof window !== "undefined") {
      const confirmed = window.confirm(
        `End "${sessionName}" now? Participants will see the leaderboard freeze on their next poll.`,
      );
      if (!confirmed) return;
    }
    startTransition(async () => {
      const result = await closeSessionAction({ sessionId });
      if (!result.ok) {
        setError(result.message);
      }
    });
  }

  return (
    <>
      <button
        type="button"
        onClick={handleClose}
        disabled={pending}
        className="vp-button vp-button-ghost vp-button-sm"
        aria-label={`End session ${sessionName}`}
      >
        {pending ? "Ending…" : "End session"}
      </button>
      {error ? (
        <span className="vp-help-text" role="alert">
          {error}
        </span>
      ) : null}
    </>
  );
}
