"use client";

import { useEffect, useRef, useState } from "react";

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
  const containerRef = useRef<HTMLDivElement | null>(null);
  const signOutButtonRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (!open) return;

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setOpen(false);
      }
    }

    function onPointerDown(event: MouseEvent | TouchEvent) {
      const target = event.target;
      if (
        containerRef.current &&
        target instanceof Node &&
        !containerRef.current.contains(target)
      ) {
        setOpen(false);
      }
    }

    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("mousedown", onPointerDown);
    window.addEventListener("touchstart", onPointerDown);

    const rafId = window.requestAnimationFrame(() => {
      signOutButtonRef.current?.focus();
    });

    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("mousedown", onPointerDown);
      window.removeEventListener("touchstart", onPointerDown);
      window.cancelAnimationFrame(rafId);
    };
  }, [open]);

  return (
    <div className="vp-user-menu-wrap" ref={containerRef}>
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        aria-label={open ? "Close account menu" : "Open account menu"}
        aria-haspopup="menu"
        aria-controls="vp-user-menu-popover"
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
        <div id="vp-user-menu-popover" role="menu" className="vp-user-menu-popover">
          <p className="vp-user-menu-email-full">
            {email}
          </p>
          <p className="vp-user-menu-meta">
            Role · {role}
          </p>
          <form action="/auth/signout" method="POST" className="vp-user-menu-form">
            <button
              ref={signOutButtonRef}
              role="menuitem"
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
