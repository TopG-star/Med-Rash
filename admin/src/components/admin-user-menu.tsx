"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

export type AdminUserMenuProps = {
  email: string;
  role: "host" | "owner";
};

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

  const triggerLabel = open
    ? `Close account menu for ${email}`
    : `Open account menu for ${email}`;

  return (
    <div className="vp-user-menu-wrap" ref={containerRef}>
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        aria-label={triggerLabel}
        title={email}
        aria-haspopup="menu"
        aria-controls="vp-user-menu-popover"
        className="vp-button vp-button-ghost vp-user-menu-trigger"
      >
        <span aria-hidden="true" className="vp-user-menu-avatar">
          {(email[0] ?? "?").toUpperCase()}
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
          {role === "owner" ? (
            <Link
              href="/account/security"
              role="menuitem"
              className="vp-button vp-button-ghost vp-user-menu-link"
              onClick={() => setOpen(false)}
            >
              Account security
            </Link>
          ) : null}
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
