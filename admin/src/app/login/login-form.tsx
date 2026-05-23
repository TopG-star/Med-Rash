"use client";

import { useActionState } from "react";

import { sendMagicLinkAction } from "./actions";
import { initialLoginState } from "./state";

export function LoginForm({ next }: { next: string }) {
  const [state, formAction, pending] = useActionState(
    sendMagicLinkAction,
    initialLoginState,
  );

  return (
    <form action={formAction} className="space-y-4">
      <input type="hidden" name="next" value={next} />
      <label className="block space-y-2">
        <span className="text-sm font-semibold">Work email</span>
        <input
          type="email"
          name="email"
          required
          autoComplete="email"
          placeholder="you@medrash.com"
          className="arena-panel w-full px-4 py-3"
        />
      </label>
      <button
        type="submit"
        disabled={pending}
        className="arena-button w-full bg-[var(--arena-primary)] px-5 py-3 font-semibold disabled:opacity-60"
      >
        {pending ? "Sending..." : "Email me a magic link"}
      </button>
      {state.status === "sent" ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-medium">
          {state.message}
        </p>
      ) : null}
      {state.status === "error" ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-danger)] px-4 py-3 text-sm font-medium">
          {state.message}
        </p>
      ) : null}
    </form>
  );
}
