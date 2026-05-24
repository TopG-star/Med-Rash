export type OnboardingActionState =
  | { status: "idle"; message: "" }
  | { status: "error"; message: string }
  | { status: "success"; message: string };

export const initialOnboardingState: OnboardingActionState = {
  status: "idle",
  message: "",
};

export const JOB_ROLES = ["MSR", "Manager"] as const;
export type JobRole = (typeof JOB_ROLES)[number];
