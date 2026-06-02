import { PostgrestError, SupabaseClient, createClient } from "@supabase/supabase-js";

export type IdentityProfile = {
  fullName: string;
  nickname: string;
  facility: string;
  specialty: string;
  // Optional recovery email. `undefined` means the client did not provide one
  // on this call and the server must NOT touch the existing column (preserves
  // a previously-saved email). `null` is reserved for an explicit clear in 6c
  // and is not yet emitted by the client.
  email?: string | null;
};

// Thrown by resolveOrCreateUserId when a write trips users_email_lower_idx.
// Handlers translate this into HTTP 409 EMAIL_TAKEN so the client can prompt
// the user to pick a different recovery email.
export class EmailTakenError extends Error {
  constructor() {
    super("That email is already linked to another profile.");
    this.name = "EmailTakenError";
  }
}

export type IdentityInput = {
  participantId: string;
  deviceInstallId: string;
  profile: IdentityProfile;
};

export type ResolvedQuiz = {
  id: string;
  slug: string;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- Supabase generic defaults to "public"; we run against the "app" schema and don't ship a generated Database type here.
let adminClient: SupabaseClient<any, "app", any, any, any> | null = null;

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function readString(value: unknown, fallback: string): string {
  return isNonEmptyString(value) ? value.trim() : fallback;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- See adminClient declaration above.
export function getSupabaseAdminClient(): SupabaseClient<any, "app", any, any, any> {
  if (adminClient) {
    return adminClient;
  }

  const url = process.env.SUPABASE_URL?.trim();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

  if (!url || !serviceRoleKey) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be configured.");
  }

  adminClient = createClient(url, serviceRoleKey, {
    db: { schema: "app" },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  return adminClient;
}

// Conservative RFC-like email shape. Intentionally not RFC-5322-complete: we
// only need to reject obvious garbage (spaces, missing @, missing dot) before
// it reaches Postgres. Final uniqueness is enforced by users_email_lower_idx.
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function parseOptionalEmail(value: unknown): string | null | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new Error("email must be a string when provided.");
  }
  const normalized = value.trim().toLowerCase();
  if (normalized.length === 0) {
    return null;
  }
  if (normalized.length > 254 || !EMAIL_REGEX.test(normalized)) {
    throw new Error("email looks malformed.");
  }
  return normalized;
}

export function parseIdentityInput(raw: Record<string, unknown>): IdentityInput {
  const participantId = readString(raw.participantId, "");
  const deviceInstallId = readString(raw.deviceInstallId, "");
  const rawProfile = raw.profile;

  if (!participantId || !deviceInstallId) {
    throw new Error("participantId and deviceInstallId are required.");
  }

  const profile =
    rawProfile && typeof rawProfile === "object" && !Array.isArray(rawProfile)
      ? (rawProfile as Record<string, unknown>)
      : {};

  const guestFallback = `Guest-${deviceInstallId.slice(0, 4).toUpperCase()}`;
  const email = parseOptionalEmail(profile.email);

  return {
    participantId,
    deviceInstallId,
    profile: {
      fullName: readString(profile.fullName, "Pilot Participant"),
      nickname: readString(profile.nickname, guestFallback),
      facility: readString(profile.facility, "Unknown Facility"),
      specialty: readString(profile.specialty, "General"),
      ...(email === undefined ? {} : { email }),
    },
  };
}

export async function resolveQuiz(
  supabase: SupabaseClient,
  quizRef: string,
): Promise<ResolvedQuiz> {
  const value = quizRef.trim();
  if (!value) {
    throw new Error("quizId is required.");
  }

  const { data, error } = await supabase
    .from("quizzes")
    .select("id, slug")
    .eq("slug", value)
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`Quiz lookup failed: ${error.message}`);
  }

  if (!data) {
    throw new Error(`Quiz slug not found: ${value}`);
  }

  return {
    id: String((data as Record<string, unknown>).id),
    slug: String((data as Record<string, unknown>).slug),
  };
}

async function upsertUserDevice(
  supabase: SupabaseClient,
  userId: string,
  deviceInstallId: string,
): Promise<void> {
  const { error } = await supabase.from("user_devices").upsert(
    {
      user_id: userId,
      device_install_id: deviceInstallId,
      is_primary: true,
    },
    {
      onConflict: "device_install_id",
    },
  );

  if (error) {
    throw new Error(`Failed to upsert user device: ${error.message}`);
  }
}

export async function resolveOrCreateUserId(
  supabase: SupabaseClient,
  identity: IdentityInput,
): Promise<string> {
  const { data: existingUser, error: existingError } = await supabase
    .from("users")
    .select("id")
    .eq("metadata->>identity_spine_id", identity.participantId)
    .limit(1)
    .maybeSingle();

  if (existingError) {
    throw new Error(`Failed to resolve user identity: ${existingError.message}`);
  }

  // Only forward `email` to the DB when the client actually sent one this
  // call. An omitted field (`undefined`) must NOT clobber a previously-saved
  // recovery email. An explicit `null` clears it (reserved for 6c settings).
  const emailColumn: { email?: string | null } =
    identity.profile.email === undefined ? {} : { email: identity.profile.email };

  if (existingUser && typeof existingUser === "object" && "id" in existingUser) {
    const userId = String((existingUser as Record<string, unknown>).id);

    // Overwrite name/facility/specialty on every resolve so profile edits
    // made on-device are reflected on the server (and therefore in the
    // leaderboard) even when the user already exists. Without this update,
    // app.users.nickname would only ever take the value supplied at the
    // first attempt-submit and stay stale forever.
    const { error: updateError } = await supabase
      .from("users")
      .update({
        full_name: identity.profile.fullName,
        nickname: identity.profile.nickname,
        facility: identity.profile.facility,
        specialty: identity.profile.specialty,
        ...emailColumn,
      })
      .eq("id", userId);

    if (updateError) {
      if (isUniqueViolation(updateError) && isEmailUniqueViolation(updateError)) {
        throw new EmailTakenError();
      }
      throw new Error(`Failed to refresh user profile: ${updateError.message}`);
    }

    await upsertUserDevice(supabase, userId, identity.deviceInstallId);
    return userId;
  }

  const { data: inserted, error: insertError } = await supabase
    .from("users")
    .insert({
      full_name: identity.profile.fullName,
      nickname: identity.profile.nickname,
      facility: identity.profile.facility,
      specialty: identity.profile.specialty,
      ...emailColumn,
      metadata: {
        identity_spine_id: identity.participantId,
        device_install_id: identity.deviceInstallId,
      },
    })
    .select("id")
    .single();

  if (insertError) {
    if (isUniqueViolation(insertError) && isEmailUniqueViolation(insertError)) {
      throw new EmailTakenError();
    }
    throw new Error(`Failed to create user from identity spine: ${insertError.message}`);
  }

  const userId = String((inserted as Record<string, unknown>).id);
  await upsertUserDevice(supabase, userId, identity.deviceInstallId);
  return userId;
}

function isEmailUniqueViolation(error: PostgrestError): boolean {
  // Match the partial unique index name created in migration 009 and the
  // column it covers. Either signal is enough; we check both because
  // PostgREST's surfaced fields vary slightly across versions.
  const haystack = `${error.message ?? ""} ${error.details ?? ""}`.toLowerCase();
  return haystack.includes("users_email_lower_idx") || haystack.includes("(lower(email))");
}

export function isUniqueViolation(error: PostgrestError): boolean {
  return error.code === "23505";
}

// ---------------------------------------------------------------------------
// Slice 6b — OTP-confirmed identity recovery on a new device.
// ---------------------------------------------------------------------------

// Anon-keyed Supabase client used purely for the auth OTP endpoints
// (signInWithOtp / verifyOtp). The service-role client cannot trigger an
// email delivery — that path requires the public auth API context.
let authClient: SupabaseClient | null = null;

export function getSupabaseAuthClient(): SupabaseClient {
  if (authClient) {
    return authClient;
  }

  const url = process.env.SUPABASE_URL?.trim();
  const anonKey = process.env.SUPABASE_ANON_KEY?.trim();

  if (!url || !anonKey) {
    throw new Error("SUPABASE_URL and SUPABASE_ANON_KEY must be configured for recovery OTP.");
  }

  authClient = createClient(url, anonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  return authClient;
}

export type RecoveryUserRow = {
  id: string;
  fullName: string;
  nickname: string;
  facility: string;
  specialty: string;
  email: string | null;
  claimedAuthUserId: string | null;
};

// Looks up an app.users row by the recovery email captured in 6a. Comparison
// is case-insensitive via the partial unique index users_email_lower_idx.
// Returns null when no profile carries that email (the caller maps this to
// PROFILE_NOT_FOUND on the recover-request endpoint).
export async function findUserByRecoveryEmail(
  supabase: SupabaseClient,
  rawEmail: string,
): Promise<RecoveryUserRow | null> {
  const normalized = rawEmail.trim().toLowerCase();
  if (!normalized || !EMAIL_REGEX.test(normalized) || normalized.length > 254) {
    return null;
  }

  const { data, error } = await supabase
    .from("users")
    .select("id, full_name, nickname, facility, specialty, email, claimed_auth_user_id")
    .ilike("email", normalized)
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`Recovery lookup failed: ${error.message}`);
  }

  if (!data) {
    return null;
  }

  const row = data as Record<string, unknown>;
  return {
    id: String(row.id),
    fullName: String(row.full_name ?? ""),
    nickname: String(row.nickname ?? ""),
    facility: String(row.facility ?? ""),
    specialty: String(row.specialty ?? ""),
    email: row.email == null ? null : String(row.email),
    claimedAuthUserId: row.claimed_auth_user_id == null ? null : String(row.claimed_auth_user_id),
  };
}

// Sets app.users.claimed_auth_user_id once an OTP has been verified. Called
// only after Supabase Auth confirms the email belongs to the verifier.
// claimed_auth_user_id is UNIQUE on app.users (migration 001), so attempting
// to bind a Supabase Auth user that already claims a different profile is
// surfaced as a 23505 the caller can map to a clean error.
//
// P7.5 INVARIANT — this function MUST only update `claimed_auth_user_id`.
// It must NEVER touch `users.metadata` or `users.metadata->>identity_spine_id`.
// The deterministic Navii avatar seed is derived from identity_spine_id, so
// any mutation here (especially during OTP claim or device recovery) would
// silently rotate every existing user's mascot. Profile-edit fields
// (full_name / nickname / facility / specialty / email) belong on the
// `resolveOrCreateUserId` upsert path, NOT here.
export async function setClaimedAuthUserId(
  supabase: SupabaseClient,
  userId: string,
  authUserId: string,
): Promise<void> {
  const { error } = await supabase
    .from("users")
    .update({ claimed_auth_user_id: authUserId })
    .eq("id", userId);

  if (error) {
    throw new Error(`Failed to bind auth user: ${error.message}`);
  }
}

// Re-points the new-device guest user_id (source) onto the recovered
// user_id (target) inside a single Postgres transaction. See
// supabase/migrations/011_user_recovery_merge.sql for the dedup policy
// (ranked best-score wins, learning attempts move wholesale, devices
// rotate, session_join_events collide-then-drop).
export async function mergeUserInto(
  supabase: SupabaseClient,
  sourceUserId: string,
  targetUserId: string,
): Promise<void> {
  if (sourceUserId === targetUserId) {
    return;
  }

  const { error } = await supabase.rpc("merge_user_into", {
    source_user_id: sourceUserId,
    target_user_id: targetUserId,
  });

  if (error) {
    throw new Error(`Failed to merge users: ${error.message}`);
  }
}

// Rotates a device install onto an arbitrary user_id. Same shape as the
// internal upsertUserDevice used during normal identity resolution, but
// exported so the recovery endpoint can rebind without going through
// resolveOrCreateUserId (which would also rewrite the profile fields).
export async function bindDeviceToUser(
  supabase: SupabaseClient,
  userId: string,
  deviceInstallId: string,
): Promise<void> {
  await upsertUserDevice(supabase, userId, deviceInstallId);
}
