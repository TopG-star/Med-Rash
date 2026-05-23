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
    <form action={action} className="flex flex-col gap-3 md:flex-row md:items-end">
      <label className="flex flex-1 flex-col gap-1">
        <span className="text-xs font-bold uppercase tracking-[0.08em] text-[var(--arena-ink-muted)]">
          Email
        </span>
        <input
          name="email"
          type="email"
          required
          placeholder="name@hospital.gh"
          className="arena-panel w-full px-4 py-3"
        />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs font-bold uppercase tracking-[0.08em] text-[var(--arena-ink-muted)]">
          Role
        </span>
        <select name="role" defaultValue="admin" className="arena-panel px-4 py-3">
          <option value="admin">admin</option>
          <option value="superadmin">superadmin</option>
        </select>
      </label>
      <button
        type="submit"
        disabled={pending}
        className="arena-button bg-[var(--arena-primary)] px-5 py-3 font-semibold disabled:opacity-60"
      >
        {pending ? "Sending…" : "Send Invitation"}
      </button>
      {state ? (
        <span
          className={
            state.ok
              ? "text-sm font-semibold text-[var(--arena-ink)]"
              : "text-sm font-semibold text-[var(--arena-danger)]"
          }
        >
          {state.message}
        </span>
      ) : null}
    </form>
  );
}
