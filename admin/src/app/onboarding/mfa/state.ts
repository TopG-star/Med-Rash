export type MfaEnrollState =
  | { status: "idle" }
  | { status: "enrolling"; factorId: string; qrSvg: string; secret: string }
  | { status: "enrolled"; recoveryCodes: string[]; nextPath: string }
  | { status: "error"; message: string };

export const initialMfaEnrollState: MfaEnrollState = { status: "idle" };

export type MfaChallengeState =
  | { status: "idle" }
  | { status: "error"; message: string; attemptsRemaining?: number };

export const initialMfaChallengeState: MfaChallengeState = { status: "idle" };

export type MfaRecoveryState =
  | { status: "idle" }
  | { status: "consumed"; remaining: number }
  | { status: "error"; message: string };

export const initialMfaRecoveryState: MfaRecoveryState = { status: "idle" };

export function safeNext(raw: unknown): string {
  return typeof raw === "string" && raw.startsWith("/") ? raw : "/dashboard";
}
