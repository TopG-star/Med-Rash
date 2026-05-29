"use server";

import { revalidatePath } from "next/cache";

import { requireAdminSession } from "@/lib/admin-session";
import {
  createSessionRecord,
  type CreateSessionInput,
  type CreateSessionResult,
} from "@/lib/session-create";
import { validateForAction } from "@/lib/schemas/_helpers";
import { createSessionSchema } from "@/lib/schemas/session";

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

  const validated = validateForAction(createSessionSchema, rawInput);
  if (!validated.ok) {
    return { ok: false, message: validated.message };
  }

  const v = validated.data;
  const input: CreateSessionInput = {
    quizId: v.quizId,
    name: v.name,
    hostName: v.hostName ?? null,
    startsAt: v.startsAt ?? null,
    endsAt: v.endsAt ?? null,
    mode: v.mode,
    metadata: v.metadata ?? {},
    createdBy: session.userId,
  };

  try {
    const data = await createSessionRecord(input);
    revalidatePath("/sessions");
    return { ok: true, data };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Failed to create session.",
    };
  }
}
