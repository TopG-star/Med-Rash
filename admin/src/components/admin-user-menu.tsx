"use client";

import { useState } from "react";

export type AdminUserMenuProps = {
  email: string;
  role: "admin" | "superadmin";
};

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}\u2026`;
}

export function AdminUserMenu({ email, role }: AdminUserMenuProps) {
  const [open, setOpen] = useState(false);

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        aria-expanded={open}
        className="arena-button flex items-center gap-2 bg-[var(--arena-surface)] px-3 py-2 text-sm font-semibold"
      >
        <span className="grid h-7 w-7 place-items-center rounded-full bg-[var(--arena-primary)] text-xs font-extrabold">
          {(email[0] ?? "?").toUpperCase()}
        </span>
        <span className="hidden sm:inline">{truncate(email, 22)}</span>
        <span className="text-[10px] font-extrabold uppercase tracking-[0.1em] text-[var(--arena-ink-muted)]">
          {role}
        </span>
      </button>
      {open ? (
        <div className="absolute right-0 z-50 mt-2 w-56 rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-panel)] p-3 shadow-lg">
          <p className="break-all text-xs font-semibold text-[var(--arena-ink-muted)]">
            {email}
          </p>
          <p className="mt-1 text-[10px] font-extrabold uppercase tracking-[0.1em] text-[var(--arena-ink-muted)]">
            Role · {role}
          </p>
          <form action="/auth/signout" method="POST" className="mt-3">
            <button
              type="submit"
              className="arena-button w-full bg-[var(--arena-danger)] px-3 py-2 text-sm font-semibold"
            >
              Sign out
            </button>
          </form>
        </div>
      ) : null}
    </div>
  );
}
