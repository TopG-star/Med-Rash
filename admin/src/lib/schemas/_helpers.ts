import { z } from "zod";

export type ValidationIssue = { path: string; message: string };

export type ValidationResult<T> =
  | { ok: true; data: T }
  | { ok: false; code: "invalid_input"; issues: ValidationIssue[] };

export function validateBody<T>(
  schema: z.ZodType<T>,
  payload: unknown,
): ValidationResult<T> {
  const parsed = schema.safeParse(payload);
  if (parsed.success) {
    return { ok: true, data: parsed.data };
  }
  const issues: ValidationIssue[] = parsed.error.issues.map((issue) => ({
    path: issue.path.join("."),
    message: issue.message,
  }));
  return { ok: false, code: "invalid_input", issues };
}

/**
 * Server-action convenience: wraps {@link validateBody} and surfaces the
 * first issue as a flat `message` so callers can return their existing
 * `{ ok: false; message }` envelope unchanged.
 */
export type ActionValidationResult<T> =
  | { ok: true; data: T }
  | { ok: false; message: string; issues: ValidationIssue[] };

export function validateForAction<T>(
  schema: z.ZodType<T>,
  payload: unknown,
): ActionValidationResult<T> {
  const result = validateBody(schema, payload);
  if (result.ok) return { ok: true, data: result.data };
  const message = result.issues[0]?.message ?? "Invalid input.";
  return { ok: false, message, issues: result.issues };
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const emailField = z.preprocess(
  (value) => (typeof value === "string" ? value.trim().toLowerCase() : value),
  z
    .string({ message: "email is required." })
    .min(1, "email is required.")
    .max(254, "email is too long.")
    .regex(EMAIL_RE, "email looks malformed."),
);

export const optionalEmailField = z
  .preprocess(
    (value) => {
      if (value === null || value === undefined) return null;
      if (typeof value !== "string") return value;
      const trimmed = value.trim().toLowerCase();
      return trimmed.length === 0 ? null : trimmed;
    },
    z
      .string()
      .max(254, "email is too long.")
      .regex(EMAIL_RE, "email looks malformed.")
      .nullable(),
  )
  .optional();

export const otpField = z.preprocess(
  (value) => (typeof value === "string" ? value.replace(/\s+/g, "") : value),
  z
    .string({ message: "Enter the 6-digit code from your email." })
    .regex(/^\d{6}$/, "Enter the 6-digit code from your email."),
);

export const nonEmptyTrimmed = (fieldName: string, max = 1024) =>
  z.preprocess(
    (value) => (typeof value === "string" ? value.trim() : value),
    z
      .string({ message: `${fieldName} is required.` })
      .min(1, `${fieldName} is required.`)
      .max(max, `${fieldName} is too long.`),
  );

export const optionalTrimmedNullable = (max = 1024) =>
  z
    .preprocess(
      (value) => {
        if (value === null || value === undefined) return null;
        if (typeof value !== "string") return value;
        const trimmed = value.trim();
        return trimmed.length === 0 ? null : trimmed;
      },
      z.string().max(max).nullable(),
    )
    .optional();

export const metadataField = z
  .preprocess(
    (value) =>
      value && typeof value === "object" && !Array.isArray(value) ? value : {},
    z.record(z.string(), z.unknown()),
  )
  .optional();
