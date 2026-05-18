import { PostgrestError, SupabaseClient, createClient } from "@supabase/supabase-js";

export type IdentityProfile = {
  fullName: string;
  nickname: string;
  facility: string;
  specialty: string;
};

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

  return {
    participantId,
    deviceInstallId,
    profile: {
      fullName: readString(profile.fullName, "Pilot Participant"),
      nickname: readString(profile.nickname, "PilotUser"),
      facility: readString(profile.facility, "Unknown Facility"),
      specialty: readString(profile.specialty, "General"),
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

  if (existingUser && typeof existingUser === "object" && "id" in existingUser) {
    const userId = String((existingUser as Record<string, unknown>).id);
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
      metadata: {
        identity_spine_id: identity.participantId,
        device_install_id: identity.deviceInstallId,
      },
    })
    .select("id")
    .single();

  if (insertError) {
    throw new Error(`Failed to create user from identity spine: ${insertError.message}`);
  }

  const userId = String((inserted as Record<string, unknown>).id);
  await upsertUserDevice(supabase, userId, identity.deviceInstallId);
  return userId;
}

export function isUniqueViolation(error: PostgrestError): boolean {
  return error.code === "23505";
}
