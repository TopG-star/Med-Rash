import { z } from "zod";
import { emailField, nonEmptyTrimmed, optionalTrimmedNullable, otpField } from "./_helpers";

export const recoverRequestSchema = z.object({
  email: emailField,
});

export const recoverVerifySchema = z.object({
  email: emailField,
  otp: otpField,
  deviceInstallId: nonEmptyTrimmed("deviceInstallId", 256),
  currentParticipantId: optionalTrimmedNullable(128),
});

export type RecoverRequestInput = z.infer<typeof recoverRequestSchema>;
export type RecoverVerifyInput = z.infer<typeof recoverVerifySchema>;
