"use server";

import { redirect } from "next/navigation";

import { getServerSupabaseClient } from "@/lib/supabase-ssr";

export type LoginActionState = {
  status: "idle" | "sent" | "error";
  message: string;
};

const INITIAL_STATE: LoginActionState = { status: "idle", message: "" };

export async function sendMagicLinkAction(
  _prev: LoginActionState,
  formData: FormData,
): Promise<LoginActionState> {
  const emailRaw = formData.get("email");
  const nextRaw = formData.get("next");

  const email = typeof emailRaw === "string" ? emailRaw.trim().toLowerCase() : "";
  const next = typeof nextRaw === "string" && nextRaw.startsWith("/")
    ? nextRaw
    : "/dashboard";

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { status: "error", message: "Enter a valid work email." };
  }

  const portalBaseUrl =
    process.env.MEDRASH_ADMIN_PORTAL_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_SITE_URL?.trim() ||
    "";

  if (!portalBaseUrl) {
    return {
      status: "error",
      message:
        "Server is missing MEDRASH_ADMIN_PORTAL_BASE_URL — set it to the deployed admin origin.",
    };
  }

  const supabase = await getServerSupabaseClient();
  const emailRedirectTo = new URL(
    `/auth/callback?next=${encodeURIComponent(next)}`,
    portalBaseUrl,
  ).toString();

  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo, shouldCreateUser: false },
  });

  if (error) {
    console.error("[login] signInWithOtp failed", error);
    return {
      status: "error",
      message: "Could not send magic link. Try again in a moment.",
    };
  }

  return {
    status: "sent",
    message: `Magic link sent to ${email}. Check your inbox.`,
  };
}

export async function signOutAndRedirectAction() {
  const supabase = await getServerSupabaseClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export const initialLoginState = INITIAL_STATE;
