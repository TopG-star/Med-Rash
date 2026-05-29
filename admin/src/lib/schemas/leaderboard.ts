import { z } from "zod";
import { nonEmptyTrimmed, optionalTrimmedNullable } from "./_helpers";
import { optionalIdentitySchema, profileSchema } from "./identity";

const limitField = z
  .preprocess((v) => {
    if (v === null || v === undefined) return 50;
    const n = typeof v === "number" ? v : Number(v);
    if (!Number.isFinite(n)) return 50;
    return Math.min(100, Math.max(1, Math.floor(n)));
  }, z.number().int().min(1).max(100))
  .optional()
  .default(50);

const seasonField = z
  .preprocess((v) => {
    if (typeof v !== "string") return null;
    const trimmed = v.trim();
    return /^\d{4}-\d{2}$/.test(trimmed) ? trimmed : null;
  }, z.string().regex(/^\d{4}-\d{2}$/).nullable())
  .optional()
  .default(null);

export const leaderboardSchema = z.object({
  type: z.enum(["monthly", "allTime"]).optional().default("allTime"),
  limit: limitField,
  season: seasonField,
  participantId: optionalTrimmedNullable(128),
  deviceInstallId: optionalTrimmedNullable(256),
  profile: profileSchema.optional(),
});

export const rankedEligibilitySchema = z.object({
  participantId: nonEmptyTrimmed("participantId", 128),
  deviceInstallId: nonEmptyTrimmed("deviceInstallId", 256),
  profile: profileSchema.optional(),
  quizId: nonEmptyTrimmed("quizId", 128),
});

export const profileSyncSchema = z.object({
  participantId: nonEmptyTrimmed("participantId", 128),
  deviceInstallId: nonEmptyTrimmed("deviceInstallId", 256),
  profile: profileSchema.optional(),
});

export { optionalIdentitySchema };

export type LeaderboardInput = z.infer<typeof leaderboardSchema>;
export type RankedEligibilityInput = z.infer<typeof rankedEligibilitySchema>;
export type ProfileSyncInput = z.infer<typeof profileSyncSchema>;
