import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type CloseSessionInput = {
  sessionId: string;
};

export type CloseSessionResult = {
  sessionId: string;
  closedAt: string;
  alreadyClosed: boolean;
};

/**
 * Stamp `closed_at = now()` on a session, idempotently.
 * Returns `alreadyClosed: true` if the row was already closed so callers
 * can render a friendly "already ended" state instead of an error.
 *
 * Liveness across the codebase is defined in app.session_is_live (see
 * migration 006); setting closed_at is the canonical "end now" override.
 */
export async function closeSessionRecord(
  input: CloseSessionInput,
): Promise<CloseSessionResult> {
  const supabase = getAdminSupabaseClient();

  const { data: existing, error: lookupErr } = await supabase
    .from("sessions")
    .select("id, closed_at")
    .eq("id", input.sessionId)
    .maybeSingle();

  if (lookupErr) {
    throw new Error(`Failed to load session: ${lookupErr.message}`);
  }
  if (!existing) {
    throw new Error("Session not found.");
  }
  if (existing.closed_at) {
    return {
      sessionId: existing.id,
      closedAt: existing.closed_at,
      alreadyClosed: true,
    };
  }

  const nowIso = new Date().toISOString();
  const { data: updated, error: updateErr } = await supabase
    .from("sessions")
    .update({ closed_at: nowIso })
    .eq("id", input.sessionId)
    .select("id, closed_at")
    .single();

  if (updateErr) {
    throw new Error(`Failed to close session: ${updateErr.message}`);
  }

  return {
    sessionId: updated.id,
    closedAt: updated.closed_at ?? nowIso,
    alreadyClosed: false,
  };
}
