"use client";

import { useActionState } from "react";

import { completeOnboardingAction } from "./actions";
import {
  initialOnboardingState,
  JOB_ROLES,
  type JobRole,
} from "./state";

type OnboardingFormProps = {
  email: string;
  defaultFullName: string;
  defaultCompany: string;
  defaultJobRole: JobRole | "";
};

export function OnboardingForm({
  email,
  defaultFullName,
  defaultCompany,
  defaultJobRole,
}: OnboardingFormProps) {
  const [state, formAction, pending] = useActionState(
    completeOnboardingAction,
    initialOnboardingState,
  );

  return (
    <form action={formAction} className="space-y-5">
      <div className="arena-panel space-y-1 px-4 py-3">
        <p className="text-xs font-extrabold uppercase tracking-[0.1em] text-[var(--arena-ink-muted)]">
          Signed in as
        </p>
        <p className="text-sm font-semibold">{email}</p>
      </div>

      <label className="block space-y-2">
        <span className="text-sm font-semibold">Full name</span>
        <input
          type="text"
          name="full_name"
          required
          minLength={2}
          maxLength={120}
          autoComplete="name"
          defaultValue={defaultFullName}
          placeholder="Dr. Priya Sharma"
          className="arena-panel w-full px-4 py-3"
        />
      </label>

      <label className="block space-y-2">
        <span className="text-sm font-semibold">Company / Hospital</span>
        <input
          type="text"
          name="company"
          required
          minLength={2}
          maxLength={120}
          autoComplete="organization"
          defaultValue={defaultCompany}
          placeholder="Acme Pharma"
          className="arena-panel w-full px-4 py-3"
        />
      </label>

      <fieldset className="space-y-2">
        <legend className="text-sm font-semibold">Job role</legend>
        <div className="flex gap-3">
          {JOB_ROLES.map((role) => (
            <label
              key={role}
              className="arena-panel flex flex-1 cursor-pointer items-center gap-2 px-4 py-3 text-sm font-semibold"
            >
              <input
                type="radio"
                name="job_role"
                value={role}
                required
                defaultChecked={defaultJobRole === role}
              />
              {role}
            </label>
          ))}
        </div>
      </fieldset>

      <button
        type="submit"
        disabled={pending}
        className="arena-button w-full bg-[var(--arena-primary)] px-5 py-3 font-semibold disabled:opacity-60"
      >
        {pending ? "Saving..." : "Finish setup"}
      </button>

      {state.status === "error" ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-danger)] px-4 py-3 text-sm font-medium">
          {state.message}
        </p>
      ) : null}
    </form>
  );
}
