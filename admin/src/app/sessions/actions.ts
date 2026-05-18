"use server";

import { revalidatePath } from "next/cache";

import {
  createSessionRecord,
  parseCreateSessionInput,
  type CreateSessionResult,
} from "@/lib/session-create";

export type CreateSessionActionResult =
  | { ok: true; data: CreateSessionResult }
  | { ok: false; message: string };

/**
 * Server Action invoked by the admin Sessions page form. Validates input,
 * inserts the session, revalidates the listing.
 *
 * Authorization: this action is only reachable through the admin app, which
 * itself is gated by the admin host's deployment policy. The Netlify HTTP
 * counterpart (session-create.ts) carries an explicit shared-secret gate for
 * scripted or external callers.
 */
export async function createSessionAction(
  rawInput: Record<string, unknown>,
): Promise<CreateSessionActionResult> {
  let parsed;
  try {
    parsed = parseCreateSessionInput(rawInput);
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Invalid session input.",
    };
  }

  try {
    const data = await createSessionRecord(parsed);
    revalidatePath("/sessions");
    return { ok: true, data };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Failed to create session.",
    };
  }
}
