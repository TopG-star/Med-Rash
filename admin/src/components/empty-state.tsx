import { ReactNode } from "react";

type EmptyStateProps = {
  icon?: ReactNode;
  title: string;
  helper: string;
  action?: ReactNode;
  className?: string;
};

export function EmptyState({
  icon,
  title,
  helper,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div
      className={[
        "arena-panel flex flex-col items-center gap-3 bg-[var(--arena-surface-muted)] p-8 text-center",
        className ?? "",
      ].join(" ")}
    >
      <div aria-hidden className="text-3xl">
        {icon ?? "\u2728"}
      </div>
      <h3 className="font-[family-name:var(--font-anybody)] text-lg font-extrabold uppercase tracking-tight">
        {title}
      </h3>
      <p className="max-w-md text-sm font-medium text-[var(--arena-ink-muted)]">
        {helper}
      </p>
      {action ? <div className="pt-2">{action}</div> : null}
    </div>
  );
}
