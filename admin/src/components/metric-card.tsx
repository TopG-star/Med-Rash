type MetricCardProps = {
  label: string;
  value: string;
  delta: string;
  subtitle?: string;
  tone?: "primary" | "secondary" | "tertiary";
};

const toneClassMap = {
  primary: "bg-[var(--arena-primary)]",
  secondary: "bg-[var(--arena-secondary)]",
  tertiary: "bg-[var(--arena-tertiary)]",
} as const;

export function MetricCard({ label, value, delta, subtitle, tone = "primary" }: MetricCardProps) {
  return (
    <div className={["arena-panel p-5", toneClassMap[tone]].join(" ")}>
      <p className="text-sm font-extrabold uppercase tracking-[0.06em] text-[var(--arena-primary-strong)]">
        {label}
      </p>
      <p className="mt-5 font-[family-name:var(--font-anybody)] text-5xl font-extrabold leading-none">
        {value}
      </p>
      <p className="mt-3 text-sm font-semibold text-[var(--arena-ink-muted)]">{delta}</p>
      {subtitle ? (
        <p className="mt-1 text-xs font-semibold text-[var(--arena-ink-muted)]">{subtitle}</p>
      ) : null}
    </div>
  );
}