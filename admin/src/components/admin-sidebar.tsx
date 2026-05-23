"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { adminNavigation } from "@/lib/design-tokens";

export type AdminSidebarUser = {
  email: string;
  role: "admin" | "superadmin";
};

type AdminSidebarProps = {
  user: AdminSidebarUser;
  onClose?: () => void;
};

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}\u2026`;
}

export function AdminSidebar({ user, onClose }: AdminSidebarProps) {
  const pathname = usePathname();
  const items = adminNavigation.filter(
    (item) => !item.requiresRole || item.requiresRole === user.role,
  );
  const initial = (user.email[0] ?? "?").toUpperCase();
  const displayRole = user.role === "superadmin" ? "Superadmin" : "Administrator";

  return (
    <aside className="arena-panel flex h-fit flex-col gap-6 bg-[var(--arena-surface)] p-5 lg:sticky lg:top-5">
      <div className="flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-full border-[3px] border-[var(--arena-outline)] bg-[var(--arena-secondary)] font-[family-name:var(--font-anybody)] text-lg font-extrabold">
            {initial}
          </div>
          <div className="min-w-0">
            <p
              title={user.email}
              className="truncate font-[family-name:var(--font-anybody)] text-base font-extrabold uppercase leading-none"
            >
              {truncate(user.email, 22)}
            </p>
            <p className="text-sm text-[var(--arena-ink-muted)]">{displayRole}</p>
          </div>
        </div>
        {onClose ? (
          <button
            type="button"
            aria-label="Close navigation"
            onClick={onClose}
            className="arena-button flex h-9 w-9 items-center justify-center bg-[var(--arena-surface)] lg:hidden"
          >
            <span aria-hidden="true" className="text-lg font-extrabold leading-none">×</span>
          </button>
        ) : null}
      </div>
      <nav className="flex flex-col gap-3">
        {items.map((item) => {
          const active = pathname.startsWith(item.href);

          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onClose}
              className={[
                "arena-button px-4 py-3 font-semibold",
                active
                  ? "bg-[var(--arena-secondary)]"
                  : "bg-[var(--arena-surface)] hover:bg-[var(--arena-panel)]",
              ].join(" ")}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}