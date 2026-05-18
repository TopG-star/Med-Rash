import { ReactNode } from "react";

import { AdminSidebar } from "@/components/admin-sidebar";

type AdminShellProps = {
  title: string;
  subtitle: string;
  actions?: ReactNode;
  children: ReactNode;
};

export function AdminShell({ title, subtitle, actions, children }: AdminShellProps) {
  return (
    <main className="mx-auto grid min-h-screen max-w-[1440px] gap-5 p-5 md:grid-cols-[280px_1fr]">
      <AdminSidebar />
      <div className="flex flex-col gap-5">
        <header className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
          <div>
            <h1 className="font-[family-name:var(--font-anybody)] text-4xl font-extrabold uppercase tracking-tight">
              {title}
            </h1>
            <p className="mt-2 max-w-3xl text-base text-[var(--arena-ink-muted)]">{subtitle}</p>
          </div>
          {actions ? <div className="flex gap-3">{actions}</div> : null}
        </header>
        {children}
      </div>
    </main>
  );
}