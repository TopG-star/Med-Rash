import { z } from "zod";
import { emailField, nonEmptyTrimmed } from "./_helpers";

export const adminRoleField = z.enum(["host", "owner"]);

export const inviteAdminSchema = z.object({
  email: emailField,
  role: adminRoleField.optional().default("host"),
});

export const userIdInputSchema = z.object({
  userId: nonEmptyTrimmed("userId", 128),
});

export const setRoleSchema = z.object({
  userId: nonEmptyTrimmed("userId", 128),
  role: adminRoleField,
});

export type InviteAdminInput = z.infer<typeof inviteAdminSchema>;
export type UserIdInput = z.infer<typeof userIdInputSchema>;
export type SetRoleInput = z.infer<typeof setRoleSchema>;
