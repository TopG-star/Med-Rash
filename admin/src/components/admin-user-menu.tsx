"use client";

import { useState } from "react";

export type AdminUserMenuProps = {
  email: string;
  role: "host" | "owner";
};

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}\u2026`;
}

export function AdminUserMenu({ email, role }: AdminUserMenuProps) {
  const [open, setOpen] = useState(false);

  return (
    <div className="vp-user-menu-wrap">
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        className="vp-button vp-button-ghost vp-user-menu-trigger"
      >
        <span className="vp-user-menu-avatar">
          {(email[0] ?? "?").toUpperCase()}
        </span>
        <span className="vp-user-menu-email hidden sm:inline">
          {truncate(email, 22)}
        </span>
        <span className="vp-user-menu-role">
          {role}
        </span>
      </button>
      {open ? (
        <div className="vp-user-menu-popover">
          <p className="vp-user-menu-email-full">
            {email}
          </p>
          <p className="vp-user-menu-meta">
            Role · {role}
          </p>
          <form action="/auth/signout" method="POST" className="vp-user-menu-form">
            <button
              type="submit"
              className="vp-button vp-button-danger vp-user-menu-signout"
            >
              Sign out
            </button>
          </form>
        </div>
      ) : null}
    </div>
  );
}
