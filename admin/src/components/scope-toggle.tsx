"use client";

import { useRouter, useSearchParams, usePathname } from "next/navigation";
import { useTransition } from "react";

export type ScopeValue = "mine" | "all";

type Props = {
  current: ScopeValue;
  /** Optional label shown above the radio group. */
  label?: string;
};

/**
 * Tiny client component that flips the `?scope=mine|all` query param and
 * navigates to the same path. Used by Sessions and Quiz Bank pages to let
 * an admin toggle between "things I created" and "everything".
 */
export function ScopeToggle({ current, label = "Scope" }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [pending, startTransition] = useTransition();

  function setScope(next: ScopeValue) {
    if (next === current) return;
    const sp = new URLSearchParams(params?.toString() ?? "");
    if (next === "all") sp.set("scope", "all");
    else sp.delete("scope"); // mine is default
    const qs = sp.toString();
    startTransition(() => {
      router.push(qs.length > 0 ? `${pathname}?${qs}` : pathname);
    });
  }

  const baseBtn =
    "arena-button px-3 py-2 text-xs font-extrabold uppercase tracking-[0.05em]";
  const active = "bg-[var(--arena-primary)]";
  const inactive = "bg-[var(--arena-surface)]";

  return (
    <div className="flex flex-col gap-1">
      <span className="text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--arena-ink-muted)]">
        {label}
      </span>
      <div className="flex gap-2" role="radiogroup" aria-label={label}>
        <button
          type="button"
          role="radio"
          aria-checked={current === "mine"}
          onClick={() => setScope("mine")}
          disabled={pending}
          className={`${baseBtn} ${current === "mine" ? active : inactive}`}
        >
          Mine
        </button>
        <button
          type="button"
          role="radio"
          aria-checked={current === "all"}
          onClick={() => setScope("all")}
          disabled={pending}
          className={`${baseBtn} ${current === "all" ? active : inactive}`}
        >
          All
        </button>
      </div>
    </div>
  );
}
