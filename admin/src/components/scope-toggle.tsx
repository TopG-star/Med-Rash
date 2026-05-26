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

  function buttonClass(isActive: boolean): string {
    return [
      "vp-toggle-btn",
      isActive ? "is-active" : "",
      pending ? "vp-disabled-soft" : "",
    ]
      .filter(Boolean)
      .join(" ");
  }

  return (
    <div className="vp-scope vp-toggle">
      <span className="vp-toggle-label">
        {label}
      </span>
      <div className="vp-toggle-group" role="group" aria-label={label}>
        <button
          type="button"
          onClick={() => setScope("mine")}
          disabled={pending}
          className={buttonClass(current === "mine")}
        >
          Mine
          {current === "mine" ? (
            <span className="vp-sr-only">Current scope</span>
          ) : null}
        </button>
        <button
          type="button"
          onClick={() => setScope("all")}
          disabled={pending}
          className={buttonClass(current === "all")}
        >
          All
          {current === "all" ? (
            <span className="vp-sr-only">Current scope</span>
          ) : null}
        </button>
      </div>
    </div>
  );
}
