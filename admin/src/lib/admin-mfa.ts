// Slice B1 P2 — MFA pure helpers.
//
// Generates recovery codes, normalises user input, hashes for comparison.
// No I/O, no Supabase client — trivially unit-testable. Server-side use
// only (callers add `import "server-only"`).

import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

const RECOVERY_CODE_GROUP_SIZE = 4;
const RECOVERY_CODE_GROUPS = 3;
// Crockford-ish base32 minus 0/1/I/O to avoid handwritten ambiguity.
const RECOVERY_CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

export const RECOVERY_CODE_COUNT = 8;

function generateOneCode(): string {
  const bytes = randomBytes(RECOVERY_CODE_GROUP_SIZE * RECOVERY_CODE_GROUPS);
  const chars: string[] = [];
  for (let i = 0; i < bytes.length; i++) {
    chars.push(
      RECOVERY_CODE_ALPHABET[bytes[i]! % RECOVERY_CODE_ALPHABET.length]!,
    );
  }
  const groups: string[] = [];
  for (let g = 0; g < RECOVERY_CODE_GROUPS; g++) {
    groups.push(
      chars
        .slice(g * RECOVERY_CODE_GROUP_SIZE, (g + 1) * RECOVERY_CODE_GROUP_SIZE)
        .join(""),
    );
  }
  return groups.join("-");
}

export function generateRecoveryCodes(count = RECOVERY_CODE_COUNT): string[] {
  if (!Number.isInteger(count) || count <= 0 || count > 32) {
    throw new Error("recovery code count must be 1..32");
  }
  const codes: string[] = [];
  const seen = new Set<string>();
  while (codes.length < count) {
    const code = generateOneCode();
    if (seen.has(code)) continue;
    seen.add(code);
    codes.push(code);
  }
  return codes;
}

/**
 * Strip dashes + whitespace, uppercase. A user typing `abcd efgh-ijkl`
 * must hash to the same value as the canonical `ABCD-EFGH-IJKL`.
 */
export function normalizeRecoveryCode(input: string): string {
  return input.replace(/[\s-]/g, "").toUpperCase();
}

export function hashRecoveryCode(input: string): string {
  return createHash("sha256").update(normalizeRecoveryCode(input)).digest("hex");
}

/**
 * Constant-time match against an array of stored hashes. Returns the
 * matching hash so the caller can `array_remove` it (single-use). Returns
 * null when no entry matches. The loop visits every hash unconditionally
 * so timing reveals nothing about which slot matched.
 */
export function matchRecoveryCode(
  input: string,
  hashes: readonly string[],
): string | null {
  const candidate = Buffer.from(hashRecoveryCode(input), "hex");
  let found: string | null = null;
  for (const h of hashes) {
    if (h.length !== candidate.length * 2) continue;
    const stored = Buffer.from(h, "hex");
    if (
      stored.length === candidate.length &&
      timingSafeEqual(stored, candidate)
    ) {
      // Don't early-return: preserve constant-time across the whole list.
      if (found === null) found = h;
    }
  }
  return found;
}
