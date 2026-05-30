"use server";

import { revalidatePath } from "next/cache";

import { requireAdminSession } from "@/lib/admin-session";
import {
  createSessionRecord,
  type CreateSessionInput,
  type CreateSessionResult,
} from "@/lib/session-create";
import { closeSessionRecord, type CloseSessionResult } from "@/lib/session-close";
import { validateForAction } from "@/lib/schemas/_helpers";
import { createSessionSchema, sessionCloseSchema } from "@/lib/schemas/session";

export type CreateSessionActionResult =
  | { ok: true; data: CreateSessionResult }
  | { ok: false; message: string };

export type CloseSessionActionResult =
  | { ok: true; data: CloseSessionResult }
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

/**
 * Server Action — flip a session into the "ended" state by stamping
 * closed_at = now(). Idempotent (returns alreadyClosed=true if the row was
 * already closed). The participant app's session leaderboard observes this
 * flip on its next poll and freezes the board.
 */
export async function closeSessionAction(
  rawInput: Record<string, unknown>,
): Promise<CloseSessionActionResult> {
  // Auth gate — requireAdminSession throws/redirects if the caller is not
  // on the allowlist. We don't need session.userId here yet (audit-log
  // slice will pick it up), but the call must stay so the action is gated.
  await requireAdminSession({ currentPath: "/sessions" });

  const validated = validateForAction(sessionCloseSchema, rawInput);
  if (!validated.ok) {
    return { ok: false, message: validated.message };
  }

  try {
    const data = await closeSessionRecord({ sessionId: validated.data.sessionId });
    revalidatePath("/sessions");
    revalidatePath(`/sessions/${validated.data.sessionId}/live`);
    revalidatePath(`/sessions/${validated.data.sessionId}/recap`);
    return { ok: true, data };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Failed to close session.",
    };
  }
}
