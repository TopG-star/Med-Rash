"use client";

import { ReactNode, useEffect, useRef, useState } from "react";

import { AdminSidebar, type AdminSidebarUser } from "@/components/admin-sidebar";
import { AdminUserMenu } from "@/components/admin-user-menu";

type AdminShellProps = {
  title: string;
  subtitle: string;
  actions?: ReactNode;
  user: AdminSidebarUser;
  children: ReactNode;
};

export function AdminShell({ title, subtitle, actions, user, children }: AdminShellProps) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const drawerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!drawerOpen) return;
    const previous = document.body.style.overflow;
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setDrawerOpen(false);
      }
    }

    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", onKey);

    const rafId = window.requestAnimationFrame(() => {
      drawerRef.current?.focus();
    });

    return () => {
      window.removeEventListener("keydown", onKey);
      window.cancelAnimationFrame(rafId);
      document.body.style.overflow = previous;
    };
  }, [drawerOpen]);

  return (
    <div className="vp-scope min-h-screen">
      <a href="#vp-main-content" className="vp-skip-link">
        Skip to main content
      </a>
      <main className="mx-auto grid w-full max-w-[1440px] gap-5 p-4 lg:grid-cols-[280px_1fr] lg:p-5">
        <div className="hidden lg:block">
          <AdminSidebar user={user} />
        </div>
        <div id="vp-main-content" className="flex min-w-0 flex-col gap-5">
          <header className="vp-shell-header">
            <div className="vp-shell-title-wrap">
              <button
                type="button"
                aria-label="Open navigation"
                aria-haspopup="dialog"
                aria-controls="vp-nav-drawer"
                onClick={() => setDrawerOpen(true)}
                className="vp-button vp-button-ghost vp-shell-nav-toggle lg:hidden"
              >
                <span aria-hidden="true" className="text-xl font-extrabold leading-none">≡</span>
              </button>
              <div className="min-w-0">
                <h1 className="vp-display vp-display-accent">
                  {title}
                </h1>
                <p className="vp-tagline vp-shell-subtitle">{subtitle}</p>
              </div>
            </div>
            <div className="vp-shell-actions">
              {actions}
              <AdminUserMenu email={user.email} role={user.role} />
            </div>
          </header>
          {children}
        </div>
      </main>

      {drawerOpen ? (
        <div className="fixed inset-0 z-50 lg:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
          <button
            type="button"
            aria-label="Close navigation"
            onClick={() => setDrawerOpen(false)}
            className="vp-shell-drawer-scrim absolute inset-0"
          />
          <div
            id="vp-nav-drawer"
            ref={drawerRef}
            tabIndex={-1}
            className="vp-shell-drawer absolute inset-y-0 left-0 w-[min(320px,85vw)] overflow-y-auto p-4"
          >
            <AdminSidebar user={user} onClose={() => setDrawerOpen(false)} />
          </div>
        </div>
      ) : null}
    </div>
  );
}