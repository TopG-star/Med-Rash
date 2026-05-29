import "server-only";

import { getAdminSupabaseClient } from "./supabase-server";

export type SessionMode = "ranked" | "learning";
export const SESSION_MODES: readonly SessionMode[] = ["ranked", "learning"] as const;
export const DEFAULT_SESSION_MODE: SessionMode = "ranked";

export type CreateSessionInput = {
  quizId: string;
  name: string;
  hostName: string | null;
  startsAt: string | null;
  endsAt: string | null;
  mode: SessionMode;
  metadata: Record<string, unknown>;
  createdBy: string | null;
};

export type CreatedSessionRow = {
  id: string;
  quizId: string;
  name: string;
  joinCode: string;
  hostName: string | null;
  startsAt: string | null;
  endsAt: string | null;
  mode: SessionMode;
  metadata: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
};

export type CreateSessionResult = {
  session: CreatedSessionRow;
  joinUrl: string;
};

// Excludes ambiguous chars (0,O,1,I,L) for QR / handwritten readability.
const JOIN_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const JOIN_CODE_LENGTH = 6;
const JOIN_CODE_MAX_ATTEMPTS = 8;

function generateJoinCode(): string {
  let out = "";
  for (let i = 0; i < JOIN_CODE_LENGTH; i += 1) {
    out += JOIN_CODE_ALPHABET.charAt(
      Math.floor(Math.random() * JOIN_CODE_ALPHABET.length),
    );
  }
  return out;
}

function buildJoinUrl(joinCode: string): string {
  return buildSessionJoinUrl(joinCode);
}

export function buildSessionJoinUrl(joinCode: string): string {
  const base =
    process.env.MEDRASH_APP_PUBLIC_BASE_URL?.trim().replace(/\/+$/, "") ?? "";
  if (!base) {
    throw new Error(
      "MEDRASH_APP_PUBLIC_BASE_URL must be configured to build session join URLs.",
    );
  }
  return `${base}/session/${encodeURIComponent(joinCode)}`;
}

type SessionInsertRow = {
  id: string;
  quiz_id: string;
  name: string;
  join_code: string;
  host_name: string | null;
  starts_at: string | null;
  ends_at: string | null;
  mode: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
};

/**
 * Pure server-side session creation, used by BOTH the Netlify HTTP handler
 * and the admin UI server action. Generates a unique join_code with bounded
 * retries on collision and returns the canonical join URL.
 *
 * Caller is responsible for authorization.
 */
export async function createSessionRecord(
  input: CreateSessionInput,
): Promise<CreateSessionResult> {
  const supabase = getAdminSupabaseClient();

  // Verify the referenced quiz exists + is active. Fail fast with a clear
  // error instead of relying on the FK constraint message.
  const { data: quiz, error: quizError } = await supabase
    .from("quizzes")
    .select("id, is_active")
    .eq("id", input.quizId)
    .maybeSingle();

  if (quizError) {
    throw new Error(`Failed to verify quiz: ${quizError.message}`);
  }
  if (!quiz) {
    throw new Error("Quiz not found for the supplied quizId.");
  }
  if ((quiz as { is_active?: boolean }).is_active === false) {
    throw new Error("Cannot create a session for an inactive quiz.");
  }

  let lastError: string | null = null;
  for (let attempt = 0; attempt < JOIN_CODE_MAX_ATTEMPTS; attempt += 1) {
    const joinCode = generateJoinCode();
    const { data, error } = await supabase
      .from("sessions")
      .insert({
        quiz_id: input.quizId,
        name: input.name,
        join_code: joinCode,
        host_name: input.hostName,
        starts_at: input.startsAt,
        ends_at: input.endsAt,
        mode: input.mode,
        metadata: input.metadata ?? {},
        created_by: input.createdBy,
      })
      .select(
        "id, quiz_id, name, join_code, host_name, starts_at, ends_at, mode, metadata, created_at, updated_at",
      )
      .single();

    if (error) {
      // 23505 = unique_violation (join_code collision). Retry.
      if ((error as { code?: string }).code === "23505") {
        lastError = error.message;
        continue;
      }
      throw new Error(`Failed to create session: ${error.message}`);
    }

    const row = data as SessionInsertRow;
    const session: CreatedSessionRow = {
      id: row.id,
      quizId: row.quiz_id,
      name: row.name,
      joinCode: row.join_code,
      hostName: row.host_name,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      mode: SESSION_MODES.includes(row.mode as SessionMode)
        ? (row.mode as SessionMode)
        : DEFAULT_SESSION_MODE,
      metadata: row.metadata ?? {},
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };

    return { session, joinUrl: buildJoinUrl(session.joinCode) };
  }

  throw new Error(
    `Failed to allocate a unique join code after ${JOIN_CODE_MAX_ATTEMPTS} attempts. Last error: ${lastError ?? "unknown"}`,
  );
}
