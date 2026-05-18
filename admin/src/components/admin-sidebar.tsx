"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { adminNavigation } from "@/lib/design-tokens";

export function AdminSidebar() {
  const pathname = usePathname();

  return (
    <aside className="arena-panel flex h-fit flex-col gap-6 bg-[var(--arena-surface)] p-5 md:sticky md:top-5">
      <div className="flex items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-full border-[3px] border-[var(--arena-outline)] bg-[var(--arena-secondary)] font-[family-name:var(--font-anybody)] text-lg font-extrabold">
          DK
        </div>
        <div>
          <p className="font-[family-name:var(--font-anybody)] text-xl font-extrabold uppercase leading-none">
            Dr. Kwame
          </p>
          <p className="text-sm text-[var(--arena-ink-muted)]">Administrator</p>
        </div>
      </div>
      <nav className="flex flex-col gap-3">
        {adminNavigation.map((item) => {
          const active = pathname.startsWith(item.href);

          return (
            <Link
              key={item.href}
              href={item.href}
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