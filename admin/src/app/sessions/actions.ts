"use server";

import { revalidatePath } from "next/cache";

import { requireAdminSession } from "@/lib/admin-session";
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
 * Authorization: the caller must be on the admin allowlist. The user's
 * Supabase id is recorded as created_by on the new session row.
 */
export async function createSessionAction(
  rawInput: Record<string, unknown>,
): Promise<CreateSessionActionResult> {
  const session = await requireAdminSession({ currentPath: "/sessions" });

  let parsed;
  try {
    parsed = parseCreateSessionInput(rawInput, session.userId);
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
