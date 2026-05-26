/**
 * Admin design-token foundation. Mirrors the structure of the Flutter
 * `ArenaDesignTokens` (Slice 1a) so the Next.js admin and the participant
 * app share semantic categories. Values follow the Vibrant Pulse arena
 * palette already established for the admin (yellow primary / cyan
 * secondary / pink tertiary), not the participant purple palette.
 *
 * Anything exported here is also wired as a CSS custom property in
 * `globals.css` under the `--arena-*` namespace so Tailwind utilities can
 * resolve them via `bg-[var(--arena-surface)]` etc.
 */

export const arenaColors = {
  background: "#f9f9f9",
  surface: "#ffffff",
  surfaceMuted: "#f3f3f3",
  surfaceContainer: "#eeeeee",

  ink: "#1b1b1b",
  inkMuted: "#4c4735",

  outline: "#111111",
  outlineMuted: "#d9d2bf",

  primary: "#ffde59",
  primaryStrong: "#705d00",
  primarySoft: "#fff1a8",

  secondary: "#73f6fb",
  secondaryStrong: "#1fd4da",
  onSecondary: "#1b1b1b",

  tertiary: "#ffd4e7",

  success: "#1b9e4b",
  successSurface: "#d8ffe4",
  warningSurface: "#ffebc2",
  error: "#c81e1e",
  dangerSurface: "#ffd8d2",

  shadow: "#111111",

  rankGold: "#ffd75e",
  rankSilver: "#c8c8c8",
  rankBronze: "#c68a4c",
} as const;

export const arenaScale = {
  borderWidth: "3px",
  shadowOffset: "4px",
  radiusLarge: "16px",
  radiusMedium: "12px",
  radiusSmall: "8px",
  pageMargin: "20px",
} as const;

export const arenaSpace = {
  xs: "4px",
  sm: "8px",
  md: "12px",
  lg: "16px",
  xl: "24px",
  xxl: "32px",
} as const;

export const arenaIconSize = {
  sm: "16px",
  md: "20px",
  lg: "24px",
  xl: "32px",
} as const;

/**
 * Aggregated token export. Prefer the named exports above when consuming
 * tokens in components; `designTokens` exists to mirror the Flutter
 * `ArenaDesignTokens` aggregate shape and to give downstream code a single
 * import surface.
 */
export const designTokens = {
  colors: arenaColors,
  scale: arenaScale,
  space: arenaSpace,
  iconSize: arenaIconSize,
  radius: {
    lg: arenaScale.radiusLarge,
    md: arenaScale.radiusMedium,
    sm: arenaScale.radiusSmall,
  },
  shadow: {
    hard: `${arenaScale.shadowOffset} ${arenaScale.shadowOffset} 0 0 ${arenaColors.shadow}`,
  },
  spacing: {
    page: arenaScale.pageMargin,
  },
} as const;

export type ArenaColorToken = keyof typeof arenaColors;
export type ArenaScaleToken = keyof typeof arenaScale;
export type ArenaSpaceToken = keyof typeof arenaSpace;
export type ArenaIconSizeToken = keyof typeof arenaIconSize;

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
