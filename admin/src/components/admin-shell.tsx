"use client";

import { ReactNode, useEffect, useState } from "react";

import { AdminSidebar } from "@/components/admin-sidebar";

type AdminShellProps = {
  title: string;
  subtitle: string;
  actions?: ReactNode;
  children: ReactNode;
};

export function AdminShell({ title, subtitle, actions, children }: AdminShellProps) {
  const [drawerOpen, setDrawerOpen] = useState(false);

  useEffect(() => {
    if (!drawerOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [drawerOpen]);

  return (
    <div className="min-h-screen">
      <main className="mx-auto grid w-full max-w-[1440px] gap-5 p-4 lg:grid-cols-[280px_1fr] lg:p-5">
        <div className="hidden lg:block">
          <AdminSidebar />
        </div>
        <div className="flex min-w-0 flex-col gap-5">
          <header className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
            <div className="flex items-start gap-3">
              <button
                type="button"
                aria-label="Open navigation"
                onClick={() => setDrawerOpen(true)}
                className="arena-button flex h-11 w-11 shrink-0 items-center justify-center bg-[var(--arena-surface)] lg:hidden"
              >
                <span aria-hidden="true" className="text-xl font-extrabold leading-none">≡</span>
              </button>
              <div className="min-w-0">
                <h1 className="font-[family-name:var(--font-anybody)] text-3xl font-extrabold uppercase tracking-tight md:text-4xl">
                  {title}
                </h1>
                <p className="mt-2 max-w-3xl text-base text-[var(--arena-ink-muted)]">{subtitle}</p>
              </div>
            </div>
            {actions ? <div className="flex flex-wrap gap-3">{actions}</div> : null}
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
            className="absolute inset-0 bg-black/40"
          />
          <div className="absolute inset-y-0 left-0 w-[min(320px,85vw)] overflow-y-auto bg-[var(--arena-background)] p-4 shadow-2xl">
            <AdminSidebar onClose={() => setDrawerOpen(false)} />
          </div>
        </div>
      ) : null}
    </div>
  );
}