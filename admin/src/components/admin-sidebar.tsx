"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { adminNavigation } from "@/lib/design-tokens";

export type AdminSidebarUser = {
  email: string;
  role: "host" | "owner";
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
  const displayRole = user.role === "owner" ? "Owner" : "Host";

  return (
    <aside className="vp-sidebar lg:sticky lg:top-5">
      <div className="vp-sidebar-head">
        <div className="vp-sidebar-profile">
          <div className="vp-sidebar-avatar">
            {initial}
          </div>
          <div className="min-w-0">
            <p
              title={user.email}
              className="vp-sidebar-email truncate"
            >
              {truncate(user.email, 22)}
            </p>
            <p className="vp-sidebar-role">{displayRole}</p>
          </div>
        </div>
        {onClose ? (
          <button
            type="button"
            aria-label="Close navigation"
            onClick={onClose}
            className="vp-button vp-button-ghost vp-sidebar-close lg:hidden"
          >
            <span aria-hidden="true" className="text-lg font-extrabold leading-none">×</span>
          </button>
        ) : null}
      </div>
      <nav className="vp-sidebar-nav" aria-label="Primary">
        {items.map((item) => {
          const active = pathname.startsWith(item.href);

          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onClose}
              aria-current={active ? "page" : undefined}
              className={`vp-sidebar-link ${active ? "is-active" : ""}`}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}