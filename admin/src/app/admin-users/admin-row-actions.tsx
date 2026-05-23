"use client";

import { useTransition, useState } from "react";

import {
  deactivateAdminAction,
  reactivateAdminAction,
  setRoleAction,
} from "./actions";

type Props = {
  userId: string;
  email: string;
  role: "host" | "owner";
  isActive: boolean;
  isSelf: boolean;
};

export function AdminRowActions({
  userId,
  email,
  role,
  isActive,
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

  const toggleActive = () => {
    if (isSelf && isActive) {
      const confirmed = window.confirm(
        `Deactivate YOUR OWN account (${email})? You will lose access immediately.`,
      );
      if (!confirmed) return;
    }
    run(() =>
      isActive ? deactivateAdminAction(userId) : reactivateAdminAction(userId),
    );
  };

  return (
    <div className="flex flex-wrap items-center gap-2">
      <button
        type="button"
        disabled={pending}
        onClick={toggleRole}
        className="arena-button bg-[var(--arena-surface)] px-3 py-1 text-xs font-bold uppercase tracking-[0.05em] disabled:opacity-60"
      >
        {role === "host" ? "Promote to Owner" : "Demote to Host"}
      </button>
      <button
        type="button"
        disabled={pending}
        onClick={toggleActive}
        className={`arena-button px-3 py-1 text-xs font-bold uppercase tracking-[0.05em] disabled:opacity-60 ${
          isActive ? "bg-[var(--arena-danger)]" : "bg-[var(--arena-primary)]"
        }`}
      >
        {isActive ? "Deactivate" : "Reactivate"}
      </button>
      {msg ? (
        <span className="text-xs font-semibold text-[var(--arena-ink)]">
          {msg}
        </span>
      ) : null}
      {err ? (
        <span className="text-xs font-semibold text-[var(--arena-danger)]">
          {err}
        </span>
      ) : null}
    </div>
  );
}
