export const designTokens = {
  colors: {
    background: "#f9f9f9",
    surface: "#ffffff",
    surfaceMuted: "#f3f3f3",
    panel: "#eeeeee",
    ink: "#1b1b1b",
    inkMuted: "#4c4735",
    outline: "#111111",
    primary: "#ffde59",
    primaryStrong: "#705d00",
    secondary: "#73f6fb",
    tertiary: "#ffd4e7",
    danger: "#ffd8d2",
    success: "#d8ffe4",
  },
  radius: {
    lg: "16px",
    md: "12px",
  },
  shadow: {
    hard: "4px 4px 0 0 #111111",
  },
  spacing: {
    page: "20px",
  },
} as const;

export type AdminNavItem = {
  href: string;
  label: string;
  requiresRole?: "owner";
};

export const adminNavigation: readonly AdminNavItem[] = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/quiz-bank", label: "Quiz Bank" },
  { href: "/sessions", label: "Sessions" },
  { href: "/reports", label: "Reports" },
  { href: "/intelligence", label: "Intelligence" },
  { href: "/admin-users", label: "Team", requiresRole: "owner" },
] as const;