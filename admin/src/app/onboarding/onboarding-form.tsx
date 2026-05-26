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
    <form action={formAction} className="vp-card">
      <div className="vp-signed-in">
        <p className="vp-signed-in-label">Signed in as</p>
        <p className="vp-signed-in-email">{email}</p>
      </div>

      <label className="vp-field">
        <span className="vp-label">Full name</span>
        <input
          type="text"
          name="full_name"
          required
          minLength={2}
          maxLength={120}
          autoComplete="name"
          defaultValue={defaultFullName}
          placeholder="Dr. Priya Sharma"
          className="vp-input"
        />
      </label>

      <label className="vp-field">
        <span className="vp-label">Company / Hospital</span>
        <input
          type="text"
          name="company"
          required
          minLength={2}
          maxLength={120}
          autoComplete="organization"
          defaultValue={defaultCompany}
          placeholder="Acme Pharma"
          className="vp-input"
        />
      </label>

      <fieldset className="vp-field">
        <legend className="vp-legend">Job role</legend>
        <div className="vp-role-grid">
          {JOB_ROLES.map((role) => (
            <label key={role} className="vp-role-option">
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
        className="vp-button vp-button-primary"
      >
        {pending ? "Saving..." : "Finish setup"}
      </button>

      {state.status === "error" ? (
        <p className="vp-banner vp-banner-error">{state.message}</p>
      ) : null}
    </form>
  );
}
