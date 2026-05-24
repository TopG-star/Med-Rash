"use client";

import { useActionState, useEffect, useState } from "react";

import { requestOtpAction, verifyOtpAction } from "./actions";
import { initialLoginState, type LoginActionState } from "./state";

function pickEmail(state: LoginActionState): string {
  if (state.status === "code_sent") return state.email;
  if (state.status === "error" && state.email) return state.email;
  return "";
}

function pickResendAt(state: LoginActionState): number | null {
  if (state.status === "code_sent") return state.nextResendAt;
  if (state.status === "error" && state.nextResendAt) return state.nextResendAt;
  return null;
}

export function LoginForm({ next }: { next: string }) {
  const [requestState, requestAction, requestPending] = useActionState(
    requestOtpAction,
    initialLoginState,
  );
  const [verifyState, verifyAction, verifyPending] = useActionState(
    verifyOtpAction,
    initialLoginState,
  );

  const onStep2 = requestState.status === "code_sent";
  const knownEmail = pickEmail(requestState) || pickEmail(verifyState);
  const resendAt = pickResendAt(requestState);
  const errorMessage =
    verifyState.status === "error"
      ? verifyState.message
      : requestState.status === "error"
        ? requestState.message
        : null;

  if (!onStep2) {
    return (
      <form action={requestAction} className="space-y-4">
        <input type="hidden" name="next" value={next} />
        <label className="block space-y-2">
          <span className="text-sm font-semibold">Work email</span>
          <input
            type="email"
            name="email"
            required
            autoComplete="email"
            defaultValue={knownEmail}
            placeholder="you@medrash.com"
            className="arena-panel w-full px-4 py-3"
          />
        </label>
        <button
          type="submit"
          disabled={requestPending}
          className="arena-button w-full bg-[var(--arena-primary)] px-5 py-3 font-semibold disabled:opacity-60"
        >
          {requestPending ? "Sending..." : "Send sign-in code"}
        </button>
        {errorMessage ? (
          <p className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-danger)] px-4 py-3 text-sm font-medium">
            {errorMessage}
          </p>
        ) : null}
      </form>
    );
  }

  return (
    <CodeStep
      next={next}
      email={knownEmail}
      resendAt={resendAt}
      requestAction={requestAction}
      verifyAction={verifyAction}
      requestPending={requestPending}
      verifyPending={verifyPending}
      sentMessage={
        requestState.status === "code_sent" ? requestState.message : null
      }
      errorMessage={errorMessage}
    />
  );
}

type CodeStepProps = {
  next: string;
  email: string;
  resendAt: number | null;
  requestAction: (formData: FormData) => void;
  verifyAction: (formData: FormData) => void;
  requestPending: boolean;
  verifyPending: boolean;
  sentMessage: string | null;
  errorMessage: string | null;
};

function CodeStep({
  next,
  email,
  resendAt,
  requestAction,
  verifyAction,
  requestPending,
  verifyPending,
  sentMessage,
  errorMessage,
}: CodeStepProps) {
  // Derive secondsLeft from a `now` ticker rather than mirroring resendAt
  // into its own state. This keeps the effect free of synchronous setState
  // calls (see react-hooks/set-state-in-effect).
  const [now, setNow] = useState(() => Date.now());
  const secondsLeft = resendAt
    ? Math.max(0, Math.ceil((resendAt - now) / 1000))
    : 0;

  useEffect(() => {
    if (!resendAt) return;
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [resendAt]);

  return (
    <div className="space-y-5">
      <form action={verifyAction} className="space-y-4">
        <input type="hidden" name="next" value={next} />
        <input type="hidden" name="email" value={email} />
        <p className="text-sm text-[var(--arena-ink-muted)]">
          We sent a 6-digit code to{" "}
          <span className="font-semibold text-[var(--arena-ink)]">{email}</span>
          . The magic link in the same email also works.
        </p>
        <label className="block space-y-2">
          <span className="text-sm font-semibold">6-digit code</span>
          <input
            type="text"
            name="token"
            required
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="\d{6}"
            maxLength={6}
            placeholder="123456"
            className="arena-panel w-full px-4 py-3 tracking-[0.4em]"
            autoFocus
          />
        </label>
        <button
          type="submit"
          disabled={verifyPending}
          className="arena-button w-full bg-[var(--arena-primary)] px-5 py-3 font-semibold disabled:opacity-60"
        >
          {verifyPending ? "Verifying..." : "Verify and sign in"}
        </button>
      </form>

      {sentMessage ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-medium">
          {sentMessage}
        </p>
      ) : null}
      {errorMessage ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-danger)] px-4 py-3 text-sm font-medium">
          {errorMessage}
        </p>
      ) : null}

      <form action={requestAction} className="flex items-center justify-between gap-3">
        <input type="hidden" name="next" value={next} />
        <input type="hidden" name="email" value={email} />
        <p className="text-xs text-[var(--arena-ink-muted)]">
          Didn&apos;t get it? Check spam or resend below.
        </p>
        <button
          type="submit"
          disabled={requestPending || secondsLeft > 0}
          className="arena-button bg-[var(--arena-surface)] px-4 py-2 text-xs font-extrabold uppercase tracking-[0.05em] disabled:opacity-60"
        >
          {secondsLeft > 0 ? `Resend in ${secondsLeft}s` : "Resend code"}
        </button>
      </form>
    </div>
  );
}
