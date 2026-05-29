import { z } from "zod";
import {
  emailField,
  nonEmptyTrimmed,
  optionalEmailField,
  optionalTrimmedNullable,
  otpField,
} from "./_helpers";

export const profileSchema = z
  .object({
    fullName: optionalTrimmedNullable(120),
    nickname: optionalTrimmedNullable(64),
    facility: optionalTrimmedNullable(160),
    specialty: optionalTrimmedNullable(120),
    email: optionalEmailField,
  })
  .partial()
  .passthrough();

export const identityInputSchema = z.object({
  participantId: nonEmptyTrimmed("participantId", 128),
  deviceInstallId: nonEmptyTrimmed("deviceInstallId", 256),
  profile: profileSchema.optional(),
});

export const optionalIdentitySchema = z
  .object({
    participantId: nonEmptyTrimmed("participantId", 128),
    deviceInstallId: optionalTrimmedNullable(256),
  })
  .nullable()
  .optional()
  .transform((value) => value ?? null);

export const loginRequestOtpSchema = z.object({
  email: emailField,
  next: optionalTrimmedNullable(512),
});

export const loginVerifyOtpSchema = z.object({
  email: emailField,
  token: otpField,
  next: optionalTrimmedNullable(512),
});

export type IdentityInput = z.infer<typeof identityInputSchema>;
export type OptionalIdentity = z.infer<typeof optionalIdentitySchema>;
export type LoginRequestOtpInput = z.infer<typeof loginRequestOtpSchema>;
export type LoginVerifyOtpInput = z.infer<typeof loginVerifyOtpSchema>;
export type ProfileInput = z.infer<typeof profileSchema>;
