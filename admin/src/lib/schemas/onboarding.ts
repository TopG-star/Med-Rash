import { z } from "zod";

import { JOB_ROLES } from "@/app/onboarding/state";

const trimmedNameField = (field: string, min: number, max: number) =>
  z.preprocess(
    (v) => (typeof v === "string" ? v.trim() : v),
    z
      .string({ message: `${field} is required.` })
      .min(min, `${field} must be at least ${min} characters.`)
      .max(max, `${field} must be at most ${max} characters.`),
  );

export const completeOnboardingSchema = z.object({
  fullName: trimmedNameField("fullName", 2, 120),
  company: trimmedNameField("company", 2, 120),
  jobRole: z.enum(JOB_ROLES, { message: "Pick a job role (MSR or Manager)." }),
});

export type CompleteOnboardingInput = z.infer<typeof completeOnboardingSchema>;
