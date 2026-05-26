"use client";

import { useTransition, useState } from "react";

import type { AdminStatus } from "@/lib/admin-users-queries";

import {
  deactivateAdminAction,
  reactivateAdminAction,
  reinviteAdminAction,
  setRoleAction,
} from "./actions";

type Props = {
  userId: string;
  role: "host" | "owner";
  isActive: boolean;
  status: AdminStatus;
  isSelf: boolean;
};

export function AdminRowActions({
  userId,
  role,
  isActive,
  status,
  isSelf,
}: Props) {
  const [pending, startTransition] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  function run(fn: () => Promise<{ ok: boolean; message: string }>) {
    setMsg(null);
    setErr(null);
    startTransition(async () => {
      const r = await fn();
      if (r.ok) setMsg(r.message);
      else setErr(r.message);
    });
  }

  const toggleRole = () =>
    run(() =>
      setRoleAction(userId, role === "host" ? "owner" : "host"),
    );

  const toggleActive = () =>
    run(() =>
      isActive ? deactivateAdminAction(userId) : reactivateAdminAction(userId),
    );

  const reinvite = () => run(() => reinviteAdminAction(userId));

  if (isSelf) {
    return (
      <span role="status" aria-live="polite" className="vp-help-text">
        You can&rsquo;t modify your own access. Ask another Owner.
      </span>
    );
  }

  const showReinvite = status === "invited" || status === "verified";

  return (
    <div className="vp-team-actions-wrap">
      <button
        type="button"
        disabled={pending}
        onClick={toggleRole}
        className={`vp-button vp-button-secondary vp-btn-sm ${pending ? "vp-disabled-soft" : ""}`}
      >
        {role === "host" ? "Promote to Owner" : "Demote to Host"}
      </button>
      <button
        type="button"
        disabled={pending}
        onClick={toggleActive}
        className={`vp-button ${isActive ? "vp-button-danger" : "vp-button-primary"} vp-btn-sm ${pending ? "vp-disabled-soft" : ""}`}
      >
        {isActive ? "Deactivate" : "Reactivate"}
      </button>
      {showReinvite ? (
        <button
          type="button"
          disabled={pending}
          onClick={reinvite}
          className={`vp-button vp-button-ghost vp-btn-sm ${pending ? "vp-disabled-soft" : ""}`}
        >
          Re-invite
        </button>
      ) : null}
      {msg ? (
        <span role="status" aria-live="polite" className="vp-help-text vp-team-note-success">
          {msg}
        </span>
      ) : null}
      {err ? (
        <span role="alert" aria-live="assertive" className="vp-help-text vp-team-note-error">
          {err}
        </span>
      ) : null}
    </div>
  );
}
