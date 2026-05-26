"use client";

import { useActionState } from "react";

import { inviteAdminAction, type AdminUsersActionResult } from "./actions";

const INITIAL: AdminUsersActionResult | null = null;

async function submit(
  _prev: AdminUsersActionResult | null,
  formData: FormData,
): Promise<AdminUsersActionResult> {
  return inviteAdminAction({
    email: formData.get("email"),
    role: formData.get("role"),
  });
}

export function InviteForm() {
  const [state, action, pending] = useActionState(submit, INITIAL);

  return (
    <form action={action} className="vp-form-grid cols-3">
      <label className="vp-field col-span-2">
        <span className="vp-label">
          Email
        </span>
        <input
          name="email"
          type="email"
          required
          placeholder="name@hospital.gh"
          className="vp-input"
        />
      </label>
      <label className="vp-field">
        <span className="vp-label">
          Role
        </span>
        <select name="role" defaultValue="host" className="vp-select">
          <option value="host">Host</option>
          <option value="owner">Owner</option>
        </select>
      </label>
      <div className="col-span-3 vp-button-row-wrap">
        <button
          type="submit"
          disabled={pending}
          className={`vp-button vp-button-primary ${pending ? "vp-disabled-soft" : ""}`}
        >
          {pending ? "Sending..." : "Send Invitation"}
        </button>
        {state ? (
          <span
            className={`vp-help-text ${state.ok ? "vp-team-note-success" : "vp-team-note-error"}`}
          >
            {state.message}
          </span>
        ) : null}
      </div>
    </form>
  );
}
