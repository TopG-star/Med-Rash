import { ReactNode } from "react";

type PanelCardProps = {
  title?: string;
  children: ReactNode;
  className?: string;
};

export function PanelCard({ title, children, className }: PanelCardProps) {
  return (
    <section className={["arena-panel bg-[var(--arena-surface)] p-5", className].join(" ")}>
      {title ? (
        <h2 className="mb-4 font-[family-name:var(--font-anybody)] text-2xl font-extrabold uppercase tracking-tight">
          {title}
        </h2>
      ) : null}
      {children}
    </section>
  );
}