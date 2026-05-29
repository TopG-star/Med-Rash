import { z } from "zod";
import {
  metadataField,
  nonEmptyTrimmed,
  optionalTrimmedNullable,
} from "./_helpers";

const isoTimestamp = z
  .preprocess((value) => {
    if (value === null || value === undefined) return null;
    if (typeof value !== "string") return value;
    const trimmed = value.trim();
    if (trimmed.length === 0) return null;
    const ms = Date.parse(trimmed);
    if (!Number.isFinite(ms)) return value;
    return new Date(ms).toISOString();
  }, z.string().datetime({ offset: true, message: "must be a valid ISO-8601 timestamp." }).nullable())
  .optional();

export const createSessionSchema = z
  .object({
    quizId: nonEmptyTrimmed("quizId", 128),
    name: nonEmptyTrimmed("name", 160),
    hostName: optionalTrimmedNullable(120),
    startsAt: isoTimestamp,
    endsAt: isoTimestamp,
    mode: z.enum(["ranked", "learning"]).optional().default("ranked"),
    metadata: metadataField,
  })
  .superRefine((value, ctx) => {
    if (value.startsAt && value.endsAt) {
      if (Date.parse(value.endsAt) < Date.parse(value.startsAt)) {
        ctx.addIssue({
          code: "custom",
          path: ["endsAt"],
          message: "endsAt must be on or after startsAt.",
        });
      }
    }
  });

export const joinCodeField = z.preprocess(
  (v) => (typeof v === "string" ? v.trim().toUpperCase() : v),
  z
    .string({ message: "joinCode is required." })
    .min(1, "joinCode is required.")
    .max(16, "joinCode is too long."),
);

export const sessionResolveSchema = z.object({
  joinCode: joinCodeField,
  participantId: optionalTrimmedNullable(128),
  deviceInstallId: optionalTrimmedNullable(256),
});

export type CreateSessionInput = z.infer<typeof createSessionSchema>;
export type SessionResolveInput = z.infer<typeof sessionResolveSchema>;
